(defpackage #:koya-tests/server/db
  (:use #:cl #:rove)
  (:import-from #:koya-server/db/connection
                #:connect-db #:disconnect-db #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/db/migrations
                #:migrate #:current-version)
  (:import-from #:koya-server/db/schema-store
                #:load-schema #:save-schema #:find-model)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-space #:make-schema
                #:schema-spaces #:space-name #:space-webhooks #:space-models #:model-name #:model-field
                #:schema->jobject)
  (:import-from #:koya/core/json
                #:to-json))
(in-package #:koya-tests/server/db)

(setup
  (connect-db ":memory:")
  (migrate))

(teardown
  (disconnect-db))

(defun schema-a ()
  (make-schema (list (make-space "website"
                                 :webhooks '("https://x/hook")
                                 :models (list (make-model "blog" :list (list (make-field :title :text :required t)
                                                                              (make-field :body :richtext)))
                                               (make-model "about" :object (list (make-field :body :richtext))))))))

(defun schema-b ()
  (make-schema (list (make-space "website"
                                 :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                              (make-field :event-at :datetime)))))
                     (make-space "shop"))))

(deftest migrations
  (ok (= (current-version) 1))
  (ok (null (migrate)) "second run applies nothing")
  (ok (fetch-one "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'contents'")))

(deftest schema-round-trip
  (ok (null (schema-spaces (load-schema))) "empty at first")
  (let ((changes (save-schema (schema-a))))
    (ok (= (length changes) 6))
    (ok (string= (to-json (schema->jobject (load-schema)))
                 (to-json (schema->jobject (schema-a))))))
  (testing "find-model reads a live copy"
    (ok (model-field (find-model "website" "blog") "title"))
    (ng (find-model "website" "nope"))
    (ng (find-model "nope" "blog")))
  (testing "saving again with no change is a no-op"
    (ok (null (save-schema (schema-a)))))
  (testing "removed models and added spaces are applied"
    (save-schema (schema-b))
    (let ((loaded (load-schema)))
      (ok (equal (mapcar #'space-name (schema-spaces loaded)) '("website" "shop")))
      (ok (equal (mapcar #'model-name (space-models (first (schema-spaces loaded)))) '("blog")))
      (ok (null (space-webhooks (first (schema-spaces loaded)))))
      (ok (model-field (find-model "website" "blog") "eventAt"))
      (ng (model-field (find-model "website" "blog") "body"))))
  (testing "removing a space deletes it"
    (save-schema (make-schema nil))
    (ok (null (schema-spaces (load-schema))))
    (ok (null (fetch "SELECT * FROM models")))))
