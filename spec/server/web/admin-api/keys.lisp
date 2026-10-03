(defpackage #:koya-spec/server/web/admin-api/keys
  (:use #:cl #:rove)
  (:import-from #:koya-spec/server/web/api-support #:admin #:delivery #:setup-api #:reset-api)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-core/json #:jobject #:jget #:json-null))
(in-package #:koya-spec/server/web/admin-api/keys)

(setup (setup-api))

(teardown (disconnect-db))

(defhook :before (reset-api))

(deftest api-keys
  (multiple-value-bind (status json) (admin :post "/admin/api/keys/website" :body (jobject "label" "second"))
    (ok (= status 201))
    (let ((key (jget json "key")) (id (jget json "id")))
      (ok (string= (subseq key 0 5) "koya_"))
      (multiple-value-bind (status) (delivery "/api/v1/website/blog" :key key)
        (ok (= status 200)))
      (multiple-value-bind (status json) (admin :get "/admin/api/keys/website")
        (ok (= status 200))
        (ok (= (length (jget json "keys")) 2))
        (ok (every (lambda (k) (null (jget k "key"))) (jget json "keys")) "plaintext never listed")
        (ok (= (length (jget json "webhookSecret")) 48)))
      (multiple-value-bind (status) (admin :delete (format nil "/admin/api/keys/website/~a" id))
        (ok (= status 200)))
      (multiple-value-bind (status) (delivery "/api/v1/website/blog" :key key)
        (ok (= status 401)))))
  (multiple-value-bind (status) (admin :get "/admin/api/keys/other")
    (ok (= status 403) "keys of another space are out of reach")))

(deftest a-key-label-is-a-string
  (dolist (label (list json-null 5))
    (multiple-value-bind (status json) (admin :post "/admin/api/keys/website" :body (jobject "label" label))
      (ok (= status 400) (format nil "~s is no label" label))
      (ok (string= (jget json "error" "code") "bad_request"))))
  (multiple-value-bind (status json) (admin :post "/admin/api/keys/website" :body (jobject))
    (ok (= status 201) "while none at all is the empty one")
    (ok (string= (jget json "label") ""))))

(deftest deleting-a-key-the-space-does-not-have
  (multiple-value-bind (status json) (admin :delete "/admin/api/keys/website/01ARZ3NDEKTSV4RRFFQ69G5FAV")
    (ok (= status 404) "is not found, rather than deleted")
    (ok (string= (jget json "error" "code") "not_found"))))
