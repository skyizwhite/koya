(defpackage #:koya-tests/server/pages/keys
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/pages/support #:request #:setup-pages #:log-in)
  (:import-from #:koya-server/db/connection #:disconnect-db)
  (:import-from #:koya-server/db/management-keys #:list-management-keys))
(in-package #:koya-tests/server/pages/keys)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest keys-page
  (let ((origin '(("origin" . "http://localhost:3000"))))
    (multiple-value-bind (status body) (request :get "/s/website/keys")
      (ok (= status 200))
      (ok (search "Delivery keys" body))
      (ok (search "Management keys" body) "both kinds of key live on the space's page")
      (ok (search "Webhook secret" body)))
    (testing "a management key is made here and shown once"
      (multiple-value-bind (status body)
          (request :post "/s/website/keys" :form '(("action" . "create-management") ("label" . "deploys")) :headers origin)
        (ok (= status 200))
        (ok (search "koya_mgmt_" body) "the plaintext is on the page that made it"))
      (ok (= (length (list-management-keys "website")) 1))
      (multiple-value-bind (status body) (request :get "/s/website/keys")
        (declare (ignore status))
        (ng (search "koya_mgmt_" body) "and never again"))
      (let ((id (getf (first (list-management-keys "website")) :id)))
        (multiple-value-bind (status) (request :post "/s/website/keys"
                                               :form `(("action" . "delete-management") ("id" . ,id)) :headers origin)
          (ok (= status 303)))
        (ok (null (list-management-keys "website")))))
    (testing "the settings page has no keys on it any more"
      (multiple-value-bind (status body) (request :get "/settings")
        (ok (= status 200))
        (ng (search "Management keys" body))))))

