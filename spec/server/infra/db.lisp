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
                #:schema->jobject #:make-custom-field #:schema-custom-fields #:custom-field-name
                #:field-fields #:field-name)
  (:import-from #:koya-server/usecases/ports/contents
                #:get-content #:list-revisions #:count-revisions)
  (:import-from #:koya-server/usecases/contents #:create #:update-draft #:publish #:destroy #:unpublish #:discard)
  (:import-from #:koya-server/domain/html #:data-text)
  (:import-from #:koya-core/json #:parse-json)
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

(defun migrated-to (version)
  (connect-db ":memory:")
  (let ((koya-server/infra/db/migrations::*migrations*
          (remove version koya-server/infra/db/migrations::*migrations* :key #'car :test #'<)))
    (migrate)))

(defun migrated-fully ()
  (connect-db ":memory:")
  (migrate))

(deftest migrations
  (ok (= (current-version) 15))
  (ok (null (migrate)) "second run applies nothing")
  (ok (fetch-one "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'contents'")))

(deftest stored-url-templates-that-are-not-web-addresses-are-dropped
  (migrated-to 9)
  (create-space "legacy")
  (exec "INSERT INTO models (space, name, kind, definition, position) VALUES (?, ?, ?, ?, ?)"
        "legacy" "about" "object"
        "{\"name\":\"about\",\"kind\":\"object\",\"fields\":[],\"previewUrl\":\"javascript:alert(1)\",\"publicUrl\":\"https://x/about\"}"
        0)
  (ok (equal (migrate) '(10 11 12 13 14 15)))
  (let ((definition (col (fetch-one "SELECT definition FROM models WHERE space = 'legacy'") "definition")))
    (ng (search "previewUrl" definition))
    (ok (search "https://x/about" definition) "a web address is kept"))
  (migrated-fully))

(deftest stored-webhooks-that-are-not-web-addresses-are-dropped
  (migrated-to 10)
  (create-space "legacy")
  (exec "UPDATE spaces SET webhooks = ? WHERE name = 'legacy'"
        "[{\"label\":\"bare\",\"url\":\"example.com/hook\"},{\"label\":\"site\",\"url\":\"https://x/hook\"},{\"label\":\"ftp\",\"url\":\"ftp://x/hook\"}]")
  (ok (equal (migrate) '(11 12 13 14 15)))
  (ok (equal (mapcar (lambda (hook) (getf hook :label)) (space-webhooks "legacy")) '("site"))
      "the space still reads, with the one hook that can be sent")
  (migrated-fully))

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

(deftest a-change-of-kind-makes-the-model-anew
  (create-space "catalog")
  (flet ((deploy-kind (kind)
           (replace-schema "catalog" (make-schema :models (list (make-model "item" kind (list (make-field :title :text)))))))
         (contents () (fetch "SELECT id FROM contents WHERE space = ?" "catalog"))
         (revisions () (col (fetch-one "SELECT COUNT(*) AS n FROM content_revisions r JOIN contents c ON c.id = r.content_id WHERE c.space = ?" "catalog") "n")))
    (deploy-kind :list)
    (create "catalog" (find-model "catalog" "item") (jobject "title" "One") :publish t)
    (create "catalog" (find-model "catalog" "item") (jobject "title" "Two"))
    (let ((changes (deploy-kind :object)))
      (ok (equal (mapcar (lambda (c) (getf c :op)) changes) '(:change-kind)))
      (ok (null (contents)) "a list turned into an object keeps none of its contents")
      (ok (zerop (revisions)) "nor their history"))
    (ok (create "catalog" (find-model "catalog" "item") (jobject "title" "Only"))
        "and takes its one content as a model made new")
    (deploy-kind :list)
    (ok (null (contents)) "an object turned into a list starts empty too")
    (delete-space "catalog")))

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
      (let ((content (get-content "magazine" (content-id published))))
        (ok (string= (content-model content) "article"))
        (ok (string= (jget (content-published content) "subtitle") "First words"))
        (ng (jget (content-published content) "lede") "the orphaned key is gone")
        (ok (string= (jget (content-published content) "title") "One") "the rest is untouched")))
    (testing "so did the draft"
      (let ((content (get-content "magazine" (content-id drafted))))
        (ok (string= (content-model content) "article"))
        (ok (string= (jget (content-draft content) "subtitle") "Later words"))))
    (testing "and the history, so an old version still restores into the field"
      (let ((data (revision-data (first (list-revisions "magazine" (content-id published))))))
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
      (let ((published (content-published (get-content "trimmed" id))))
        (ng (nth-value 1 (gethash "summary" published)))
        (ng (nth-value 1 (gethash "rank" published)))
        (ok (string= (jget published "title") "One") "the rest is untouched")))
    (testing "so does the draft"
      (let ((draft (content-draft (get-content "trimmed" id))))
        (ng (nth-value 1 (gethash "summary" draft)))
        (ng (nth-value 1 (gethash "rank" draft)))
        (ok (string= (jget draft "title") "One, again"))))
    (testing "and the history"
      (dolist (revision (list-revisions "trimmed" id))
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
      (ng (nth-value 1 (gethash "summary" (content-published (get-content "trimmed" id)))))))
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
        (let ((published (content-published (get-content "pointed" post))))
          (ng (nth-value 1 (gethash "tag" published)))
          (ok (string= (jget published "title") "One") "the rest is untouched")))
      (testing "so the tag is deleted with nothing left pointing at it"
        (ok (destroy "pointed" (find-model "pointed" "tag") tag))
        (ng (get-content "pointed" tag)))))
  (delete-space "pointed"))

(deftest stored-values-of-fields-that-are-gone-are-dropped
  (migrated-to 11)
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
  (ok (equal (migrate) '(12 13 14 15)))
  (let ((content (get-content "leftover" "kept")))
    (ng (nth-value 1 (gethash "gone" (content-published content))))
    (ng (nth-value 1 (gethash "gone" (content-draft content))))
    (ok (string= (jget (content-published content) "title") "Live") "a declared field is kept")
    (ok (eq (jget (content-published content) "flag") nil) "as the value it was")
    (ok (nth-value 1 (gethash "flag" (content-published content))))
    (ok (string= (jget (content-draft content) "title") "Next")))
  (let ((data (revision-data (first (list-revisions "leftover" "kept")))))
    (ng (nth-value 1 (gethash "gone" data)) "the history loses it too")
    (ok (string= (jget data "title") "Old")))
  (migrated-fully))

(defun text-fits-p (data text)
  (if (null data)
      (null text)
      (and text (equalp (parse-json text) (data-text (parse-json data))))))

(defun texts-fit-p (space)
  (every (lambda (row)
           (and (text-fits-p (col row "published") (col row "published_text"))
                (text-fits-p (col row "draft") (col row "draft_text"))))
         (fetch "SELECT published, draft, published_text, draft_text FROM contents WHERE space = ?" space)))

(deftest the-text-of-each-content-is-kept-beside-it
  (create-space "texts")
  (flet ((deploy (&rest fields)
           (replace-schema "texts" (make-schema :models (list (make-model "post" :list fields)))))
         (post () (find-model "texts" "post")))
    (deploy (make-field :title :text) (make-field :body :richtext) (make-field :count :number))
    (let ((draft (content-id (create "texts" (post) (jobject "title" "Draft" "body" "<p>a <b>draft</b></p>"))))
          (live (content-id (create "texts" (post) (jobject "title" "Live" "body" "<p>live</p>") :publish t)))
          (numbers (content-id (create "texts" (post) (jobject "count" 3)))))
      (ok (texts-fit-p "texts") "a content made, as a draft or published")
      (ok (string= (col (fetch-one "SELECT draft_text FROM contents WHERE id = ?" numbers) "draft_text") "{}")
          "data without strings has an empty text, so a draft is never read through to the published one")
      (ok (null (col (fetch-one "SELECT published_text FROM contents WHERE id = ?" draft) "published_text"))
          "and no data has no text")
      (update-draft "texts" (post) live (jobject "title" "Live, edited"))
      (ok (texts-fit-p "texts") "a draft saved")
      (publish "texts" (post) live :data (jobject "title" "Live, edited" "body" "<p>again</p>"))
      (ok (texts-fit-p "texts") "published")
      (update-draft "texts" (post) live (jobject "title" "Next"))
      (discard "texts" (post) live)
      (ok (texts-fit-p "texts") "a draft discarded")
      (unpublish "texts" (post) live)
      (ok (texts-fit-p "texts") "unpublished")
      (deploy (make-field :headline :text :was :title) (make-field :body :richtext) (make-field :count :number))
      (ok (texts-fit-p "texts") "a field renamed by a deploy")
      (deploy (make-field :headline :text) (make-field :count :number))
      (ok (texts-fit-p "texts") "a field dropped")
      (deploy (make-field :headline :richtext) (make-field :count :number))
      (ok (texts-fit-p "texts") "a field whose type changed")
      (ok (null (gethash "headline" (parse-json (col (fetch-one "SELECT draft_text FROM contents WHERE id = ?" live)
                                                    "draft_text"))))
          "takes its old text with it")))
  (delete-space "texts"))

(deftest a-content-stored-before-its-text-gets-one
  (migrated-to 13)
  (create-space "older")
  (exec "INSERT INTO models (space, name, kind, definition, position) VALUES (?, ?, ?, ?, ?)"
        "older" "post" "list"
        "{\"name\":\"post\",\"kind\":\"list\",\"fields\":[{\"name\":\"body\",\"type\":\"richtext\"},{\"name\":\"n\",\"type\":\"number\"}]}"
        0)
  (flet ((row (id status published draft)
           (exec "INSERT INTO contents (id, space, model, status, published, draft, created_at, updated_at)
                  VALUES (?, 'older', 'post', ?, ?, ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')"
                 id status published draft)))
    (row "drafted" "draft" nil "{\"body\":\"<p>new &amp; <b>bold</b></p>\"}")
    (row "live" "published" "{\"body\":\"<p>live</p>\"}" nil)
    (row "both" "published+draft" "{\"body\":\"<p>old</p>\"}" "{\"body\":\"<p>new</p>\"}")
    (row "bare" "draft" nil "{\"n\":1}"))
  (ok (equal (migrate) '(14 15)))
  (ok (texts-fit-p "older") "every content gets the text of its data")
  (ok (string= (col (fetch-one "SELECT draft_text FROM contents WHERE id = 'drafted'") "draft_text")
               "{\"body\":\"new & bold\"}"))
  (ok (string= (col (fetch-one "SELECT draft_text FROM contents WHERE id = 'bare'") "draft_text") "{}"))
  (migrated-fully))

(deftest a-deploy-leaves-a-record
  (create-space "logged")
  (replace-schema "logged"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text)
                                                                         (make-field :lede :text)))))
               :by "key:ci")
  (replace-schema "logged"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text :required t))))))
  (let ((deploys (list-deploys "logged")))
    (ok (= (count-deploys "logged") 2))
    (ok (= (length deploys) 2))

    (let ((first-deploy (find 3 deploys :key #'deploy-change-count))
          (second-deploy (find 2 deploys :key #'deploy-change-count)))
      (ok (= (deploy-change-count first-deploy) 3) "a model and the fields in it")
      (ok (string= (deploy-by first-deploy) "key:ci")
          "stored as what the server knew, not as the words a page shows")
      (ng (deploy-destructive first-deploy))
      (ok (equal (mapcar #'change-op (deploy-changes first-deploy)) '("add_model" "add_field" "add_field")))
      (ok (deploy-destructive second-deploy) "removing a field takes its values")
      (ok (string= (deploy-by second-deploy) "") "a deploy with nobody named says so by saying nothing")
      (ok (search "options tightened (required none -> true)"
                  (change-description (find "change_field_options" (deploy-changes second-deploy)
                                            :key #'change-op :test #'equal)))
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
  (let ((both (list-revisions "old" "both")))
    (ok (equal (mapcar #'revision-event both) '("draft" "publish")) "the draft sits on top of the published data")
    (ok (string= (jget (revision-data (second both)) "title") "Live"))
    (ok (string= (revision-created-at (second both)) "2026-02-01T00:00:00.000Z") "published when it was last revised")
    (ok (string= (revision-created-at (first both)) "2026-03-01T00:00:00.000Z")))
  (ok (equal (mapcar #'revision-event (list-revisions "old" "draft")) '("draft")))
  (migrated-fully))

(deftest content-ids-belong-to-their-space
  (migrated-to 12)
  (exec "INSERT INTO spaces (name, webhook_secret, created_at) VALUES ('one', 's', '2026-01-01T00:00:00.000Z')")
  (exec "INSERT INTO models (space, name, kind, definition) VALUES ('one', 'post', 'list', '{\"name\":\"post\",\"kind\":\"list\",\"fields\":[{\"name\":\"title\",\"type\":\"text\"}]}')")
  (exec "INSERT INTO contents (id, space, model, status, published, created_at, updated_at, published_at, revised_at)
         VALUES ('about', 'one', 'post', 'published', '{\"title\":\"One\"}',
                 '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')")
  (exec "INSERT INTO content_revisions (content_id, event, data, created_at)
         VALUES ('about', 'publish', '{\"title\":\"One\"}', '2026-01-01T00:00:00.000Z')")
  (ok (equal (migrate) '(13 14 15)))
  (testing "what was stored moves into its space, history and all"
    (ok (string= (jget (content-published (get-content "one" "about")) "title") "One"))
    (ok (equal (mapcar #'revision-event (list-revisions "one" "about")) '("publish"))))
  (testing "another space may hold a content of the same id"
    (create-space "two")
    (replace-schema "two" (make-schema :models (list (make-model "post" :list (list (make-field :title :text))))))
    (ok (create "two" (find-model "two" "post") (jobject "title" "Two") :id "about" :publish t))
    (ok (string= (jget (content-published (get-content "two" "about")) "title") "Two"))
    (ok (string= (jget (content-published (get-content "one" "about")) "title") "One") "and neither touches the other")
    (ok (= (count-revisions "two" "about") 1))
    (ok (= (count-revisions "one" "about") 1))
    (destroy "two" (find-model "two" "post") "about")
    (ng (get-content "two" "about"))
    (ok (get-content "one" "about") "deleting one leaves the other")
    (ok (= (count-revisions "one" "about") 1) "with its history"))
  (testing "within a space an id is still one content"
    (ok (signals (create "one" (find-model "one" "post") (jobject "title" "Again") :id "about")
                 'koya-server/domain/errors:conflict)))
  (migrated-fully))

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

(defun seo-schema (&rest seo-fields)
  (make-schema :custom-fields (list (make-custom-field "seo" seo-fields))
               :models (list (make-model "post" :list (list (make-field :title :text)
                                                          (make-field :meta :custom :custom-field "seo"))))))

(deftest custom-fields-are-kept-with-the-space
  (create-space "kept")
  (replace-schema "kept" (seo-schema (make-field :title :text) (make-field :image :media)))
  (let ((schema (load-schema "kept")))
    (ok (equal (mapcar #'custom-field-name (schema-custom-fields schema)) '("seo")))
    (ok (equal (mapcar #'field-name (field-fields (model-field (find-model "kept" "post") "meta"))) '("title" "image"))
        "and a model read back has them in its custom field"))
  (replace-schema "kept" (make-schema :models (list (make-model "post" :list (list (make-field :title :text))))))
  (ok (null (schema-custom-fields (load-schema "kept"))) "and a deploy without them drops them")
  (delete-space "kept"))

(deftest a-field-removed-from-a-custom-field-takes-its-values-with-it
  (create-space "inner")
  (replace-schema "inner" (seo-schema (make-field :title :text) (make-field :note :text)))
  (let* ((content (create "inner" (find-model "inner" "post")
                          (jobject "title" "Post" "meta" (jobject "title" "Searchable" "note" "Gone soon")) :publish t))
         (id (content-id content)))
    (ok (string= (jget (data-text (content-published content)) "meta" "title") "Searchable")
        "the text of a custom field is kept with the rest, field by field")
    (let ((changes (replace-schema "inner" (seo-schema (make-field :title :text)))))
      (ok (member :remove-field (mapcar (lambda (c) (getf c :op)) changes))))
    (let ((meta (jget (content-published (get-content "inner" id)) "meta")))
      (ng (nth-value 1 (gethash "note" meta)) "the value inside is gone")
      (ok (string= (jget meta "title") "Searchable") "and the rest stays"))
    (ok (null (search "Gone soon" (fetch-text "inner" id))) "and so is its text")
    (dolist (revision (list-revisions "inner" id))
      (ng (nth-value 1 (gethash "note" (jget (revision-data revision) "meta"))) "and the history's")))
  (delete-space "inner"))

(defun fetch-text (space id)
  (col (first (fetch "SELECT published_text FROM contents WHERE space = ? AND id = ?" space id)) "published_text"))

(defun blocks-schema (&rest heading-fields)
  (make-schema :custom-fields (list (make-custom-field "heading" heading-fields)
                                    (make-custom-field "quote" (list (make-field :text :text) (make-field :note :text))))
               :models (list (make-model "post" :list (list (make-field :title :text)
                                                          (make-field :blocks :repeater :custom-fields '(heading quote)))))))

(deftest a-field-removed-from-a-row-kind-leaves-the-other-rows
  (create-space "rows")
  (replace-schema "rows" (blocks-schema (make-field :text :text) (make-field :note :text)))
  (let* ((content (create "rows" (find-model "rows" "post")
                          (jobject "title" "P" "blocks" (vector (jobject "fieldId" "heading" "text" "Head" "note" "Gone")
                                                                (jobject "fieldId" "quote" "text" "Quoted" "note" "Kept")))
                          :publish t))
         (id (content-id content)))
    (replace-schema "rows" (blocks-schema (make-field :text :text)))
    (let ((rows (jget (content-published (get-content "rows" id)) "blocks")))
      (ng (nth-value 1 (gethash "note" (aref rows 0))) "the field goes from the rows of its custom field")
      (ok (string= (jget (aref rows 1) "note") "Kept") "and stays in rows of another")
      (ok (string= (jget (aref rows 0) "text") "Head")))
    (ng (search "Gone" (fetch-text "rows" id)) "its text goes too")
    (ok (search "Quoted" (fetch-text "rows" id)) "the text of every row is kept")
    (dolist (revision (list-revisions "rows" id))
      (ng (nth-value 1 (gethash "note" (aref (jget (revision-data revision) "blocks") 0))) "and the history's")))
  (delete-space "rows"))
