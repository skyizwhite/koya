(defpackage #:koya-tests/server/db
  (:use #:cl #:rove)
  (:import-from #:koya-server/db/connection
                #:connect-db #:disconnect-db #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/db/migrations
                #:migrate #:current-version)
  (:import-from #:koya-server/db/schema-dump
                #:migrated-snapshot #:read-snapshot)
  (:import-from #:koya-server/db/schema-store
                #:load-schema #:save-schema #:find-model
                #:list-spaces #:create-space #:delete-space #:find-space)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-schema #:make-webhook
                #:schema-webhooks #:schema-models #:model-name #:model-field
                #:schema->jobject)
  (:import-from #:koya-server/db/sessions
                #:make-session-store #:purge-expired-sessions)
  (:import-from #:lack/middleware/session/store
                #:fetch-session #:store-session #:remove-session)
  (:import-from #:koya/core/json
                #:to-json))
(in-package #:koya-tests/server/db)

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
  (ok (= (current-version) 6))
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
    (save-schema "shop" (schema-b))
    (delete-space "shop")
    (ng (find-space "shop"))
    (ok (null (load-schema "shop")))
    (ok (null (fetch "SELECT * FROM models WHERE space = 'shop'")))))

(deftest schema-round-trip
  (create-space "site")
  (ok (null (schema-models (load-schema "site"))) "empty at first")
  (let ((changes (save-schema "site" (schema-a))))
    (ok (= (length changes) 6))
    (ok (string= (to-json (schema->jobject (load-schema "site")))
                 (to-json (schema->jobject (schema-a))))))
  (testing "find-model reads a live copy"
    (ok (model-field (find-model "site" "blog") "title"))
    (ng (find-model "site" "nope"))
    (ng (find-model "nope" "blog")))
  (testing "saving again with no change is a no-op"
    (ok (null (save-schema "site" (schema-a)))))
  (testing "removed models are applied"
    (save-schema "site" (schema-b))
    (let ((loaded (load-schema "site")))
      (ok (equal (mapcar #'model-name (schema-models loaded)) '("blog")))
      (ok (null (schema-webhooks loaded)))
      (ok (model-field (find-model "site" "blog") "eventAt"))
      (ng (model-field (find-model "site" "blog") "body"))))
  (testing "an empty schema leaves the space with no models"
    (save-schema "site" (make-schema))
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
