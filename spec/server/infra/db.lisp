(defpackage #:koya-spec/server/infra/db
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/ports/deploys #:list-deploys #:count-deploys)
  (:import-from #:koya-server/usecases/schema #:replace-schema)
  (:import-from #:koya-server/infra/db/connection
                #:connect-db #:disconnect-db #:exec #:fetch #:fetch-one #:col #:with-db-transaction)
  (:import-from #:koya-core/time #:iso-from-now)
  (:import-from #:koya-server/infra/db/migrations #:migrate #:current-version)
  (:import-from #:koya-server/infra/db/schema-dump #:migrated-snapshot #:read-snapshot)
  (:import-from #:koya-server/usecases/ports/spaces
                #:load-schema #:find-model #:list-spaces #:delete-space #:space-webhooks
                #:find-space)
  (:import-from #:koya-server/usecases/spaces #:create-space)
  (:import-from #:koya-server/domain/deploy
                #:deploy-changes #:deploy-change-count #:deploy-destructive #:deploy-by
                #:change-description #:change-op)
  (:import-from #:koya-core/schema
                #:make-field #:make-model #:make-schema #:make-webhook
                #:schema-webhooks #:schema-models #:model-name #:model-field
                #:schema->jobject)
  (:import-from #:koya-server/usecases/ports/contents
                #:get-content #:list-revisions)
  (:import-from #:koya-server/usecases/contents #:create #:update-draft #:publish #:destroy)
  (:import-from #:koya-core/diff
                #:destructive-changes-p)
  (:import-from #:koya-server/usecases/ports/sessions #:make-session-store #:delete-sessions)
  (:import-from #:koya-server/infra/db/sessions #:purge-expired-sessions)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-model #:content-published #:content-draft)
  (:import-from #:koya-server/domain/revision
                #:revision-event #:revision-data #:revision-created-at)
  (:import-from #:lack/middleware/session/store
                #:fetch-session #:store-session #:remove-session)
  (:import-from #:koya-core/json
                #:to-json #:jobject #:jget))
(in-package #:koya-spec/server/infra/db)

(setup
  (connect-db ":memory:")
  (migrate))

(teardown
  (disconnect-db))

(defun schema-a ()
  (make-schema :webhooks (list (make-webhook "hook" "https://x/hook"))
               :models (list (make-model "blog" :list (list (make-field :title :text :required t)
                                                            (make-field :body :richtext)))
                             (make-model "about" :object (list (make-field :body :richtext))))))

(defun schema-b ()
  (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                            (make-field :event-at :datetime))))))

(deftest migrations
  (ok (= (current-version) 12))
  (ok (null (migrate)) "second run applies nothing")
  (ok (fetch-one "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'contents'")))

(deftest stored-url-templates-that-are-not-web-addresses-are-dropped
  (create-space "legacy")
  (exec "INSERT INTO models (space, name, kind, definition, position) VALUES (?, ?, ?, ?, ?)"
        "legacy" "about" "object"
        "{\"name\":\"about\",\"kind\":\"object\",\"fields\":[],\"previewUrl\":\"javascript:alert(1)\",\"publicUrl\":\"https://x/about\"}"
        0)
  (exec "DELETE FROM schema_version WHERE version >= 10")
  (ok (equal (migrate) '(10 11 12)))
  (let ((definition (col (fetch-one "SELECT definition FROM models WHERE space = 'legacy'") "definition")))
    (ng (search "previewUrl" definition))
    (ok (search "https://x/about" definition) "a web address is kept"))
  (delete-space "legacy"))

(deftest stored-webhooks-that-are-not-web-addresses-are-dropped
  (create-space "legacy")
  (exec "UPDATE spaces SET webhooks = ? WHERE name = 'legacy'"
        "[{\"label\":\"bare\",\"url\":\"example.com/hook\"},{\"label\":\"site\",\"url\":\"https://x/hook\"},{\"label\":\"ftp\",\"url\":\"ftp://x/hook\"}]")
  (exec "DELETE FROM schema_version WHERE version >= 11")
  (ok (equal (migrate) '(11 12)))
  (ok (equal (mapcar (lambda (hook) (getf hook :label)) (space-webhooks "legacy")) '("site"))
      "the space still reads, with the one hook that can be sent")
  (delete-space "legacy"))

(deftest schema-snapshot-matches-the-migrations

  (ok (equal (migrated-snapshot) (read-snapshot))
      "src/server/infra/db/schema.sql is current; regenerate it with (koya-server:write-schema-snapshot)"))

(deftest spaces-are-made-here-not-by-a-deploy
  (ok (null (load-schema "website")) "no space, no schema")
  (ok (string= (create-space "website") "website"))
  (ok (create-space "shop"))
  (ok (equal (mapcar (lambda (s) (getf s :name)) (list-spaces)) '("website" "shop"))
      "in the order they were made")
  (ok (= (getf (first (list-spaces)) :models) 0))
  (testing "bad and taken names are refused"
    (ok (signals (create-space "My Space") 'error))
    (ok (signals (create-space "website") 'error)))
  (testing "deleting takes the space's models with it"
    (replace-schema "shop" (schema-b))
    (delete-space "shop")
    (ng (find-space "shop"))
    (ok (null (load-schema "shop")))
    (ok (null (fetch "SELECT * FROM models WHERE space = 'shop'")))))

(deftest schema-round-trip
  (create-space "site")
  (ok (null (schema-models (load-schema "site"))) "empty at first")
  (let ((changes (replace-schema "site" (schema-a))))
    (ok (= (length changes) 6))
    (ok (string= (to-json (schema->jobject (load-schema "site")))
                 (to-json (schema->jobject (schema-a))))))
  (testing "find-model reads a live copy"
    (ok (model-field (find-model "site" "blog") "title"))
    (ng (find-model "site" "nope"))
    (ng (find-model "nope" "blog")))
  (testing "saving again with no change is a no-op"
    (ok (null (replace-schema "site" (schema-a)))))
  (testing "removed models are applied"
    (replace-schema "site" (schema-b))
    (let ((loaded (load-schema "site")))
      (ok (equal (mapcar #'model-name (schema-models loaded)) '("blog")))
      (ok (null (schema-webhooks loaded)))
      (ok (model-field (find-model "site" "blog") "eventAt"))
      (ng (model-field (find-model "site" "blog") "body"))))
  (testing "an empty schema leaves the space with no models"
    (replace-schema "site" (make-schema))
    (ok (null (schema-models (load-schema "site"))))
    (ok (find-space "site") "the space itself stays")
    (ok (null (fetch "SELECT * FROM models")))))

(defun owner-session ()
  (let ((session (make-hash-table :test 'equal)))
    (setf (gethash "owner" session) t)
    session))

(defun session-count ()
  (col (fetch-one "SELECT COUNT(*) AS n FROM sessions") "n"))

(defmacro with-secret ((secret) &body body)
  (let ((saved (gensym)))
    `(let ((,saved (uiop:getenv "KOYA_SECRET")))
       (setf (uiop:getenv "KOYA_SECRET") ,secret)
       (unwind-protect (progn ,@body)
         (setf (uiop:getenv "KOYA_SECRET") (or ,saved ""))))))

(deftest sessions-outlive-the-store
  (exec "DELETE FROM sessions")
  (with-secret ("first-secret-long-enough-to-log-in-with")
    (store-session (make-session-store) "sid-1" (owner-session))
    (let ((loaded (fetch-session (make-session-store) "sid-1")))
      (ok (hash-table-p loaded))
      (ok (gethash "owner" loaded) "the owner flag survives"))
    (testing "the id is not stored, so the database holds no session anyone can use"
      (ok (= (session-count) 1))
      (ng (fetch-one "SELECT id FROM sessions WHERE id = ?" "sid-1")))
    (testing "every use moves the end a full day away"
      (exec "UPDATE sessions SET expires_at = ?" (iso-from-now 3600))
      (store-session (make-session-store) "sid-1" (owner-session))
      (ok (string> (col (fetch-one "SELECT expires_at FROM sessions") "expires_at") (iso-from-now (- (* 24 3600) 60)))
          "although the data did not change"))
    (testing "a session that has run out is refused and purged"
      (exec "UPDATE sessions SET expires_at = ?" "2000-01-01T00:00:00.000Z")
      (ng (fetch-session (make-session-store) "sid-1"))
      (purge-expired-sessions)
      (ok (zerop (session-count))))
    (testing "logging out drops the row"
      (store-session (make-session-store) "sid-2" (owner-session))
      (remove-session (make-session-store) "sid-2")
      (ng (fetch-session (make-session-store) "sid-2"))
      (ok (zerop (session-count))))))

(deftest a-new-secret-ends-every-session
  (exec "DELETE FROM sessions")
  (with-secret ("first-secret-long-enough-to-log-in-with")
    (store-session (make-session-store) "sid-1" (owner-session)))
  (with-secret ("second-secret-long-enough-to-log-in-with")
    (ng (fetch-session (make-session-store) "sid-1") "a session made under another secret is no session"))
  (with-secret ("first-secret-long-enough-to-log-in-with")
    (ok (fetch-session (make-session-store) "sid-1") "and the secret alone decides it")))

(deftest sessions-end-all-but-one
  (exec "DELETE FROM sessions")
  (with-secret ("first-secret-long-enough-to-log-in-with")
    (dolist (sid '("sid-1" "sid-2" "sid-3"))
      (store-session (make-session-store) sid (owner-session)))
    (delete-sessions :except "sid-2")
    (ok (fetch-session (make-session-store) "sid-2") "the one kept")
    (ng (fetch-session (make-session-store) "sid-1"))
    (ng (fetch-session (make-session-store) "sid-3"))
    (delete-sessions)
    (ok (zerop (session-count)) "and with none kept, every one")))

(deftest a-session-ended-during-a-request-stays-ended
  (exec "DELETE FROM sessions")
  (with-secret ("first-secret-long-enough-to-log-in-with")
    (store-session (make-session-store) "sid-1" (owner-session))
    (let ((session (fetch-session (make-session-store) "sid-1")))
      (delete-sessions)
      (store-session (make-session-store) "sid-1" session)
      (ng (fetch-session (make-session-store) "sid-1")
          "writing back what the request read does not bring it back"))
    (testing "while a login moves what was read to a new id"
      (store-session (make-session-store) "sid-2" (owner-session))
      (let ((session (fetch-session (make-session-store) "sid-2")))
        (remove-session (make-session-store) "sid-2")
        (store-session (make-session-store) "sid-3" session)
        (ok (fetch-session (make-session-store) "sid-3"))))))

(deftest a-rename-carries-the-content-with-it
  (create-space "magazine")
  (replace-schema "magazine"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text)
                                                                        (make-field :lede :text))))))
  (let ((published (create "magazine" (find-model "magazine" "post") (jobject "title" "One" "lede" "First words") :publish t))
        (drafted (create "magazine" (find-model "magazine" "post") (jobject "title" "Two" "lede" "Later words"))))
    (let ((changes (replace-schema "magazine"
                                (make-schema :models (list (make-model "article" :list
                                                                       (list (make-field :title :text)
                                                                             (make-field :subtitle :text :was :lede))
                                                                       :was 'post))))))
      (ok (equal (mapcar (lambda (c) (getf c :op)) changes) '(:rename-model :rename-field)))
      (ng (destructive-changes-p changes) "a rename loses nothing, so it needs no force"))
    (ok (equal (mapcar #'model-name (schema-models (load-schema "magazine"))) '("article")))
    (testing "the published data moved with the model and the field"
      (let ((content (get-content (content-id published))))
        (ok (string= (content-model content) "article"))
        (ok (string= (jget (content-published content) "subtitle") "First words"))
        (ng (jget (content-published content) "lede") "the orphaned key is gone")
        (ok (string= (jget (content-published content) "title") "One") "the rest is untouched")))
    (testing "so did the draft"
      (let ((content (get-content (content-id drafted))))
        (ok (string= (content-model content) "article"))
        (ok (string= (jget (content-draft content) "subtitle") "Later words"))))
    (testing "and the history, so an old version still restores into the field"
      (let ((data (revision-data (first (list-revisions (content-id published))))))
        (ok (string= (jget data "subtitle") "First words"))
        (ng (jget data "lede"))))
    (testing "the stored schema keeps the shape, not the rename"
      (ok (null (search "\"was\"" (to-json (schema->jobject (load-schema "magazine"))))))
      (ok (null (replace-schema "magazine"
                             (make-schema :models (list (make-model "article" :list
                                                                    (list (make-field :title :text)
                                                                          (make-field :subtitle :text :was :lede))
                                                                    :was 'post)))))
          "deploying the same source again changes nothing"))))

(deftest a-removed-field-takes-its-values-with-it
  (create-space "trimmed")
  (replace-schema "trimmed"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text)
                                                                        (make-field :summary :text)
                                                                        (make-field :rank :text))))))
  (let* ((content (create "trimmed" (find-model "trimmed" "post")
                          (jobject "title" "One" "summary" "Short" "rank" "high") :publish t))
         (id (content-id content)))
    (update-draft "trimmed" (find-model "trimmed" "post") id (jobject "title" "One, again"))
    (let ((changes (replace-schema "trimmed"
                                (make-schema :models (list (make-model "post" :list
                                                                       (list (make-field :title :text)
                                                                             (make-field :rank :number))))))))
      (ok (equal (mapcar (lambda (c) (getf c :op)) changes) '(:remove-field :change-field-type))))
    (testing "the published data loses the removed field and the retyped one"
      (let ((published (content-published (get-content id))))
        (ng (nth-value 1 (gethash "summary" published)))
        (ng (nth-value 1 (gethash "rank" published)))
        (ok (string= (jget published "title") "One") "the rest is untouched")))
    (testing "so does the draft"
      (let ((draft (content-draft (get-content id))))
        (ng (nth-value 1 (gethash "summary" draft)))
        (ng (nth-value 1 (gethash "rank" draft)))
        (ok (string= (jget draft "title") "One, again"))))
    (testing "and the history"
      (dolist (revision (list-revisions id))
        (ng (nth-value 1 (gethash "summary" (revision-data revision))))
        (ng (nth-value 1 (gethash "rank" (revision-data revision))))))
    (testing "so a write of one field and a publish of the draft are checked against the model alone"
      (ok (update-draft "trimmed" (find-model "trimmed" "post") id (jobject "rank" 1)))
      (ok (publish "trimmed" (find-model "trimmed" "post") id)))
    (testing "a field added again under the old name starts empty"
      (replace-schema "trimmed"
                   (make-schema :models (list (make-model "post" :list
                                                          (list (make-field :title :text)
                                                                (make-field :rank :number)
                                                                (make-field :summary :text))))))
      (ng (nth-value 1 (gethash "summary" (content-published (get-content id)))))))
  (delete-space "trimmed"))

(deftest a-reference-pointed-at-another-model-takes-its-values-with-it
  (create-space "pointed")
  (flet ((deploy (target)
           (replace-schema "pointed"
                           (make-schema :models (list (make-model "tag" :list (list (make-field :name :text)))
                                                      (make-model "cat" :list (list (make-field :name :text)))
                                                      (make-model "post" :list
                                                                  (list (make-field :title :text)
                                                                        (make-field :tag :reference :model target))))))))
    (deploy "tag")
    (let* ((tag (content-id (create "pointed" (find-model "pointed" "tag") (jobject "name" "Lisp") :publish t)))
           (post (content-id (create "pointed" (find-model "pointed" "post")
                                     (jobject "title" "One" "tag" tag) :publish t))))
      (ok (equal (mapcar (lambda (c) (getf c :op)) (deploy "cat")) '(:change-field-type)))
      (testing "the post no longer names the tag"
        (let ((published (content-published (get-content post))))
          (ng (nth-value 1 (gethash "tag" published)))
          (ok (string= (jget published "title") "One") "the rest is untouched")))
      (testing "so the tag is deleted with nothing left pointing at it"
        (ok (destroy "pointed" (find-model "pointed" "tag") tag))
        (ng (get-content tag)))))
  (delete-space "pointed"))

(deftest stored-values-of-fields-that-are-gone-are-dropped
  (create-space "leftover")
  (exec "INSERT INTO models (space, name, kind, definition, position) VALUES (?, ?, ?, ?, ?)"
        "leftover" "post" "list"
        "{\"name\":\"post\",\"kind\":\"list\",\"fields\":[{\"name\":\"title\",\"type\":\"text\"},{\"name\":\"flag\",\"type\":\"boolean\"}]}"
        0)
  (exec "INSERT INTO contents (id, space, model, status, published, draft, created_at, updated_at)
         VALUES ('kept', 'leftover', 'post', 'published+draft',
                 '{\"title\":\"Live\",\"flag\":false,\"gone\":\"x\"}', '{\"title\":\"Next\",\"gone\":[1]}',
                 '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
  (exec "INSERT INTO content_revisions (content_id, event, data, created_at)
         VALUES ('kept', 'publish', '{\"title\":\"Old\",\"gone\":{\"a\":1}}', '2026-01-01T00:00:00.000Z')")
  (exec "DELETE FROM schema_version WHERE version >= 12")
  (ok (equal (migrate) '(12)))
  (let ((content (get-content "kept")))
    (ng (nth-value 1 (gethash "gone" (content-published content))))
    (ng (nth-value 1 (gethash "gone" (content-draft content))))
    (ok (string= (jget (content-published content) "title") "Live") "a declared field is kept")
    (ok (eq (jget (content-published content) "flag") nil) "as the value it was")
    (ok (nth-value 1 (gethash "flag" (content-published content))))
    (ok (string= (jget (content-draft content) "title") "Next")))
  (let ((data (revision-data (first (list-revisions "kept")))))
    (ng (nth-value 1 (gethash "gone" data)) "the history loses it too")
    (ok (string= (jget data "title") "Old")))
  (delete-space "leftover"))

(deftest a-deploy-leaves-a-record
  (create-space "logged")
  (replace-schema "logged"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text)))))
               :by "key:ci")
  (replace-schema "logged"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text :required t))))))
  (let ((deploys (list-deploys "logged")))
    (ok (= (count-deploys "logged") 2))
    (ok (= (length deploys) 2))

    (let ((first-deploy (find 2 deploys :key #'deploy-change-count))
          (second-deploy (find 1 deploys :key #'deploy-change-count)))
      (ok (= (deploy-change-count first-deploy) 2) "a model and the field in it")
      (ok (string= (deploy-by first-deploy) "key:ci")
          "stored as what the server knew, not as the words a page shows")
      (ng (deploy-destructive first-deploy))
      (ok (equal (mapcar #'change-op (deploy-changes first-deploy)) '("add_model" "add_field")))
      (ok (deploy-destructive second-deploy) "requiring a field can reject what is stored")
      (ok (string= (deploy-by second-deploy) "") "a deploy with nobody named says so by saying nothing")
      (ok (search "options tightened (required none -> true)"
                  (change-description (first (deploy-changes second-deploy))))
          "the log says which option moved and where to, not only that one did")))
  (testing "a deploy that changed nothing is not an event"
    (replace-schema "logged"
                 (make-schema :models (list (make-model "post" :list (list (make-field :title :text :required t))))))
    (ok (= (count-deploys "logged") 2)))
  (testing "the log goes with the space"
    (delete-space "logged")
    (ok (= (count-deploys "logged") 0))))

(deftest existing-contents-start-their-history
  (connect-db ":memory:")
  (let ((koya-server/infra/db/migrations::*migrations*
          (remove 9 koya-server/infra/db/migrations::*migrations* :key #'car :test #'<=)))
    (migrate))
  (exec "INSERT INTO spaces (name, webhook_secret, created_at) VALUES ('old', 's', '2026-01-01T00:00:00.000Z')")
  (exec "INSERT INTO models (space, name, kind, definition) VALUES ('old', 'post', 'list', '{\"fields\":[{\"name\":\"title\",\"type\":\"text\"}]}')")
  (exec "INSERT INTO contents (id, space, model, status, published, draft, created_at, updated_at, published_at, revised_at)
         VALUES ('both', 'old', 'post', 'published+draft', '{\"title\":\"Live\"}', '{\"title\":\"Next\"}',
                 '2026-01-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z', '2026-02-01T00:00:00.000Z'),
                ('draft', 'old', 'post', 'draft', NULL, '{\"title\":\"Only\"}',
                 '2026-01-01T00:00:00.000Z', '2026-01-05T00:00:00.000Z', NULL, NULL)")
  (migrate)
  (let ((both (list-revisions "both")))
    (ok (equal (mapcar #'revision-event both) '("draft" "publish")) "the draft sits on top of the published data")
    (ok (string= (jget (revision-data (second both)) "title") "Live"))
    (ok (string= (revision-created-at (second both)) "2026-02-01T00:00:00.000Z") "published when it was last revised")
    (ok (string= (revision-created-at (first both)) "2026-03-01T00:00:00.000Z")))
  (ok (equal (mapcar #'revision-event (list-revisions "draft")) '("draft")))
  (connect-db ":memory:")
  (migrate))

(deftest a-rolled-back-deploy-leaves-nothing
  (create-space "rolled")
  (replace-schema "rolled" (schema-a))
  (ok (= (count-deploys "rolled") 1))
  (handler-case
      (with-db-transaction
        (replace-schema "rolled" (schema-b))
        (ok (model-field (find-model "rolled" "blog") "eventAt") "inside, the new schema is read")
        (error "abandoned"))
    (error () nil))
  (ng (model-field (find-model "rolled" "blog") "eventAt") "the schema read inside is not kept")
  (ok (find-model "rolled" "about"))
  (ok (= (count-deploys "rolled") 1) "and the deploy is not in the log")
  (delete-space "rolled"))

(deftest a-session-row-holds-what-it-was-last-given
  (exec "DELETE FROM sessions")
  (with-secret ("first-secret-long-enough-to-log-in-with")
    (let ((session (owner-session)))
      (store-session (make-session-store) "sid-3" session)
      (testing "a changed one is written"
        (setf (gethash "toast" session) "saved")
        (store-session (make-session-store) "sid-3" session)
        (ok (string= (jget (fetch-session (make-session-store) "sid-3") "toast") "saved"))
        (ok (= (session-count) 1) "in the same row"))
      (testing "a row that cannot be read is no session"
        (exec "UPDATE sessions SET data = ?" "{not json")
        (ng (fetch-session (make-session-store) "sid-3"))))))
