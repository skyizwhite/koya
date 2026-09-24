(defpackage #:koya-tests/server/web/admin-api/schema
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/web/api-support #:*management-key* #:test-schema #:request #:admin #:setup-api #:reset-api)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema #:make-webhook #:schema->jobject)
  (:import-from #:koya/core/json #:jobject #:jget))
(in-package #:koya-tests/server/web/admin-api/schema)

(setup (setup-api))

(teardown (disconnect-db))

(defhook :before (reset-api))

(deftest boolean-default
  (multiple-value-bind (status json)
      (admin :post "/admin/api/contents/website/blog" :body (jobject "data" (jobject "title" "Defaulted") "publish" t))
    (ok (= status 201))
    (ok (eq (jget json "published" "featured") t) "a :boolean with :default t starts true when not given"))
  (multiple-value-bind (status json)
      (admin :post "/admin/api/contents/website/blog" :body (jobject "data" (jobject "title" "Explicit" "featured" nil) "publish" t))
    (ok (= status 201))
    (ok (eq (jget json "published" "featured") nil) "an explicit false is kept")))

(deftest schema-endpoints
  (multiple-value-bind (status json) (admin :get "/admin/api/schema/website")
    (ok (= status 200))
    (ok (= (length (jget json "models")) 3)))
  (let ((new (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)))))))
    (multiple-value-bind (status json) (admin :post "/admin/api/schema/website/plan" :body (schema->jobject new))
      (ok (= status 200))
      (ok (eq (jget json "destructive") t))
      (ok (plusp (length (jget json "changes")))))
    (multiple-value-bind (status json) (admin :put "/admin/api/schema/website" :body (schema->jobject new))
      (ok (= status 409))
      (ok (string= (jget json "error" "code") "destructive_changes"))
      (ok (plusp (length (jget json "error" "details")))))
    (multiple-value-bind (status json) (admin :get "/admin/api/schema/website")
      (ok (= status 200))
      (ok (= (length (jget json "models")) 3) "not applied")))
  (testing "non-destructive push applies without force"
    (let ((new (make-schema :webhooks (list (make-webhook "hook" "https://example.com/hook"))
                            :models (list (make-model "blog" :list (list (make-field :title :text :required t :unique t)
                                                                         (make-field :body :richtext)
                                                                         (make-field :featured :boolean :default t)
                                                                         (make-field :tags :reference :model "tag" :many t)
                                                                         (make-field :cover :media)
                                                                         (make-field :extra :text)))
                                          (make-model "tag" :list (list (make-field :name :text :required t)))
                                          (make-model "about" :object (list (make-field :body :richtext)))))))
      (multiple-value-bind (status json) (admin :put "/admin/api/schema/website" :body (schema->jobject new))
        (ok (= status 200))
        (ok (= (length (jget json "applied")) 1))
        (ok (string= (jget (aref (jget json "applied") 0) "op") "add_field")))
      ;; restore
      (admin :put "/admin/api/schema/website" :body (schema->jobject (test-schema)) :query "force=true")))
  (testing "a management key reaches its own space and no other"
    (multiple-value-bind (status json) (admin :get "/admin/api/schema/other")
      (ok (= status 403))
      (ok (string= (jget json "error" "code") "forbidden")))
    (multiple-value-bind (status) (admin :put "/admin/api/schema/other" :body (schema->jobject (test-schema)))
      (ok (= status 403))))
  (testing "invalid schema is a 400"
    (multiple-value-bind (status json) (admin :put "/admin/api/schema/website" :body (jobject "koyaSchema" 1 "models" (vector (jobject "name" "Bad Name" "kind" "list"))))
      (ok (= status 400))
      (ok (string= (jget json "error" "code") "invalid_schema"))))
  (testing "malformed JSON is a 400"
    (multiple-value-bind (status json) (request :put "/admin/api/schema/website" :headers `(("authorization" . ,(format nil "Bearer ~a" *management-key*))) :body "not json")
      (ok (= status 400))
      (ok (string= (jget json "error" "code") "bad_json")))))

