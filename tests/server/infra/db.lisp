(defpackage #:koya-tests/server/infra/db
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/schema/deploy #:replace-schema)
  (:import-from #:koya-server/infra/db/connection
                #:connect-db #:disconnect-db #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/infra/db/migrations #:migrate #:current-version)
  (:import-from #:koya-server/infra/db/schema-dump #:migrated-snapshot #:read-snapshot)
  (:import-from #:koya-server/usecases/ports/spaces
                #:load-schema #:find-model #:list-spaces #:delete-space
                #:find-space #:list-deploys #:count-deploys)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:create-space)
  (:import-from #:koya-server/domain/deploy
                #:deploy-changes #:deploy-change-count #:deploy-destructive #:deploy-by
                #:change-description #:change-op)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-schema #:make-webhook
                #:schema-webhooks #:schema-models #:model-name #:model-field
                #:schema->jobject)
  (:import-from #:koya-server/usecases/ports/contents
                #:create-content #:get-content #:list-revisions)
  (:import-from #:koya/core/diff
                #:destructive-changes-p)
  (:import-from #:koya-server/usecases/ports/sessions #:make-session-store)
  (:import-from #:koya-server/infra/db/sessions #:purge-expired-sessions)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-model #:content-published #:content-draft)
  (:import-from #:koya-server/domain/revision
                #:revision-event #:revision-data #:revision-created-at)
  (:import-from #:lack/middleware/session/store
                #:fetch-session #:store-session #:remove-session)
  (:import-from #:koya/core/json
                #:to-json #:jobject #:jget))
(in-package #:koya-tests/server/infra/db)

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
  (ok (= (current-version) 9))
  (ok (null (migrate)) "second run applies nothing")
  (ok (fetch-one "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'contents'")))

(deftest schema-snapshot-matches-the-migrations
  ;; the snapshot is generated, so a mismatch means it was not regenerated after
  ;; a migration was added, never that it is the schema that is wrong
  (ok (equal (migrated-snapshot) (read-snapshot))
      "src/server/db/schema.sql is current; regenerate it with (koya-server:write-schema-snapshot)"))

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

(deftest sessions-outlive-the-store
  (let ((session (make-hash-table :test 'equal)))
    (setf (gethash "owner" session) t)
    (store-session (make-session-store) "sid-1" session))
  ;; a fresh store is what a restarted process has: the session comes from the row
  (let ((loaded (fetch-session (make-session-store) "sid-1")))
    (ok (hash-table-p loaded))
    (ok (gethash "owner" loaded) "the owner flag survives"))
  (testing "a session that has run out is refused and purged"
    (exec "UPDATE sessions SET expires_at = ? WHERE id = ?" "2000-01-01T00:00:00.000Z" "sid-1")
    (ng (fetch-session (make-session-store) "sid-1"))
    (purge-expired-sessions)
    (ng (fetch-one "SELECT id FROM sessions WHERE id = ?" "sid-1")))
  (testing "logging out drops the row"
    (let ((session (make-hash-table :test 'equal)))
      (setf (gethash "owner" session) t)
      (store-session (make-session-store) "sid-2" session))
    (remove-session (make-session-store) "sid-2")
    (ng (fetch-session (make-session-store) "sid-2"))))

(deftest a-rename-carries-the-content-with-it
  (create-space "magazine")
  (replace-schema "magazine"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text)
                                                                        (make-field :lede :text))))))
  (let ((published (create-content "magazine" "post" (jobject "title" "One" "lede" "First words") :publish t))
        (drafted (create-content "magazine" "post" (jobject "title" "Two" "lede" "Later words"))))
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
    ;; found by what they carry, not by where they sit: two rows written in the
    ;; same millisecond carry ULIDs that do not say which came first, and a test
    ;; writes both faster than a person could deploy twice
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
  ;; a database from before the history, holding what production held then
  (connect-db ":memory:")
  (let ((koya-server/infra/db/migrations::*migrations*
          (remove 9 koya-server/infra/db/migrations::*migrations* :key #'car :test #'<=)))
    (migrate))
  (exec "INSERT INTO spaces (name, webhook_secret, created_at) VALUES ('old', 's', '2026-01-01T00:00:00.000Z')")
  (exec "INSERT INTO models (space, name, kind, definition) VALUES ('old', 'post', 'list', '{}')")
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
