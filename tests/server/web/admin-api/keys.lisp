(defpackage #:koya-tests/server/web/admin-api/keys
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/web/api-support #:admin #:delivery #:setup-api #:reset-api)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-core/json #:jobject #:jget))
(in-package #:koya-tests/server/web/admin-api/keys)

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
