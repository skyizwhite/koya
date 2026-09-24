(defpackage #:koya-tests/server/pages/keys
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/pages/support #:request #:request-url #:call-action #:setup-pages #:log-in)
  (:import-from #:koya-server/pages/s/<space>/keys #:create-key #:delete-key #:rotate-secret)
  (:import-from #:koya-server/db/delivery-keys #:list-delivery-keys)
  (:import-from #:koya-server/db/schema-store #:space-webhook-secret)
  (:import-from #:koya-server/db/connection #:disconnect-db)
  (:import-from #:koya-server/db/management-keys #:list-management-keys))
(in-package #:koya-tests/server/pages/keys)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest keys-page
  (multiple-value-bind (status body) (request :get "/s/website/keys")
    (ok (= status 200))
    (ok (search "Delivery keys" body))
    (ok (search "Management keys" body) "both kinds of key live on the space's page")
    (ok (search "Webhook secret" body)))
  (testing "a management key is made here and shown once"
    (multiple-value-bind (status body)
        (call-action :post (create-key :space "website" :kind "management") :form '(("label" . "deploys")))
      (ok (= status 200))
      (ok (search "koya_mgmt_" body) "the plaintext is in the answer that made it"))
    (ok (= (length (list-management-keys "website")) 1))
    (multiple-value-bind (status body) (request :get "/s/website/keys")
      (declare (ignore status))
      (ng (search "koya_mgmt_" body) "and never again"))
    (let ((id (getf (first (list-management-keys "website")) :id)))
      (ok (= 200 (call-action :post (delete-key :space "website" :kind "management") :form `(("id" . ,id)))))
      (ok (null (list-management-keys "website")))))
  (testing "the settings page has no keys on it any more"
    (multiple-value-bind (status body) (request :get "/settings")
      (ok (= status 200))
      (ng (search "Management keys" body)))))

(deftest keys-are-worked-on-in-place
  (testing "the page's forms call the actions"
    (multiple-value-bind (status body) (request :get "/s/website/keys")
      (ok (= status 200))
      (ok (search (format nil "hx-post=\"~a" (subseq (create-key) 0 (position #\? (create-key)))) body))
      (ok (search "hx-confirm=" body) "deleting and rotating ask first")))
  (testing "creating answers the section with the key shown once"
    (multiple-value-bind (status body) (call-action :post (create-key :space "website" :kind "delivery")
                                                    :form '(("label" . "site")))
      (ok (= status 200))
      (ok (search "id=\"delivery-keys\"" body))
      (ok (search "Copy it now" body))
      (ok (search "koya_" body))
      (ng (search "<html" body) "a fragment, not a page"))
    (ok (= (length (list-delivery-keys "website")) 1)))
  (testing "deleting answers the section and a toast out of band"
    (let ((id (getf (first (list-delivery-keys "website")) :id)))
      (multiple-value-bind (status body) (call-action :post (delete-key :space "website" :kind "delivery")
                                                      :form `(("id" . ,id)))
        (ok (= status 200))
        (ok (search "No keys yet." body))
        (ok (search "id=\"toast\" hx-swap-oob=\"true\"" body))
        (ok (search "Key deleted." body)))
      (ok (null (list-delivery-keys "website")))))
  (testing "rotating answers the secret's section"
    (let ((before (space-webhook-secret "website")))
      (multiple-value-bind (status body) (call-action :post (rotate-secret :space "website"))
        (ok (= status 200))
        (ok (search (space-webhook-secret "website") body))
        (ng (search before body)))))
  (testing "a space or a kind that does not exist is refused, and the page is left alone"
    (multiple-value-bind (status body headers) (call-action :post (create-key :space "nope" :kind "delivery"))
      (ok (= status 404))
      (ok (equal (getf headers :hx-reswap) "none"))
      (ok (search "hx-swap-oob" body)))
    (ok (= 404 (call-action :post (create-key :space "website" :kind "admin")))))
  (testing "only htmx reaches an action"
    (ok (= 400 (request-url :post (create-key :space "website" :kind "delivery")
                            :headers '(("origin" . "http://localhost:3000")))))
    (ok (null (list-delivery-keys "website")) "and nothing was made")
    (ok (= 404 (request :post "/s/website/keys" :headers '(("origin" . "http://localhost:3000"))))
        "the page itself takes no posts")))
