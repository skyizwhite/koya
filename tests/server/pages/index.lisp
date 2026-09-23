(defpackage #:koya-tests/server/pages/index
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/pages/support #:request #:setup-pages #:log-in)
  (:import-from #:koya-server/db/connection #:disconnect-db)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/delivery-keys #:create-delivery-key #:list-delivery-keys)
  (:import-from #:koya-server/db/management-keys #:create-management-key #:list-management-keys)
  (:import-from #:koya-server/db/delivery-keys #:list-delivery-keys))
(in-package #:koya-tests/server/pages/index)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest spaces-page
  (let ((origin '(("origin" . "http://localhost:3000"))))
    (multiple-value-bind (status body) (request :get "/")
      (ok (= status 200))
      (ok (search "website" body))
      (ok (search "data-dialog-open=\"new-space\"" body) "the form is behind a button")
      (ok (search "<dialog id=\"new-space\"" body) "and lives in a dialog on the page"))
    (testing "a space is made here, and starts empty"
      (multiple-value-bind (status headers) (request :post "/" :form '(("action" . "create") ("name" . "shop")) :headers origin)
        (declare (ignore headers))
        (ok (= status 303)))
      (ok (find-space "shop"))
      (multiple-value-bind (status body) (request :get "/s/shop")
        (ok (= status 200))
        (ok (search "This space has no models" body))))
    (testing "a bad or taken name is refused, and says why"
      (request :post "/" :form '(("action" . "create") ("name" . "shop")) :headers origin)
      (multiple-value-bind (status body) (request :get "/")
        (declare (ignore status))
        (ok (search "already exists" body) "the flash carries the reason"))
      (request :post "/" :form '(("action" . "create") ("name" . "Not A Slug")) :headers origin)
      (multiple-value-bind (status body) (request :get "/")
        (declare (ignore status))
        (ok (search "lowercase letters" body))))
    (testing "deleting takes the space and its keys with it"
      (create-delivery-key "shop" :label "gone")
      (create-management-key "shop" :label "gone")
      (multiple-value-bind (status) (request :post "/" :form '(("action" . "create") ("name" . "shop")) :headers origin)
        (declare (ignore status)))
      (multiple-value-bind (status) (request :post "/" :form '(("action" . "delete") ("name" . "shop")) :headers origin)
        (ok (= status 303)))
      (ng (find-space "shop"))
      (ok (null (list-delivery-keys "shop")))
      (ok (null (list-management-keys "shop")))
      (multiple-value-bind (status) (request :get "/s/shop")
        (ok (= status 404))))
    (testing "an unknown space cannot be deleted"
      (multiple-value-bind (status) (request :post "/" :form '(("action" . "delete") ("name" . "ghost")) :headers origin)
        (ok (= status 404))))))

