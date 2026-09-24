(defpackage #:koya-tests/server/pages/index
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/pages/support #:request #:call-action #:setup-pages #:log-in)
  (:import-from #:koya-server/pages/index #:create-space-action #:delete-space-action)
  (:import-from #:koya-server/db/connection #:disconnect-db)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/delivery-keys #:create-delivery-key #:list-delivery-keys)
  (:import-from #:koya-server/db/management-keys #:create-management-key #:list-management-keys)
  (:import-from #:koya-server/db/delivery-keys #:list-delivery-keys))
(in-package #:koya-tests/server/pages/index)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest spaces-page
  (multiple-value-bind (status body) (request :get "/")
    (ok (= status 200))
    (ok (search "website" body))
    (ok (search "commandfor=\"new-space\"" body) "the form is behind a button")
    (ok (search "<dialog id=\"new-space\"" body) "and lives in a dialog on the page")
    (ok (search (format nil "hx-post=\"~a\"" (create-space-action)) body)))
  (testing "a space is made here, and starts empty"
    (ok (= 200 (call-action :post (create-space-action) :form '(("name" . "shop")))))
    (ok (find-space "shop"))
    (multiple-value-bind (status body) (request :get "/s/shop")
      (ok (= status 200))
      (ok (search "This space has no models" body))))
  (testing "a bad or taken name is refused, and says why"
    (ok (search "already exists" (nth-value 1 (call-action :post (create-space-action) :form '(("name" . "shop"))))))
    (ok (search "lowercase letters"
                (nth-value 1 (call-action :post (create-space-action) :form '(("name" . "Not A Slug")))))))
  (testing "deleting takes the space and its keys with it"
    (create-delivery-key "shop" :label "gone")
    (create-management-key "shop" :label "gone")
    (ok (= 200 (call-action :post (delete-space-action) :form '(("name" . "shop")))))
    (ng (find-space "shop"))
    (ok (null (list-delivery-keys "shop")))
    (ok (null (list-management-keys "shop")))
    (ok (= 404 (request :get "/s/shop"))))
  (testing "an unknown space cannot be deleted"
    (ok (= 404 (call-action :post (delete-space-action) :form '(("name" . "ghost"))))))
  (testing "the page takes no posts: what is done here is an action"
    (ok (= 404 (request :post "/" :form '(("name" . "shop")) :headers '(("origin" . "http://localhost:3000")))))))

(deftest spaces-are-made-and-deleted-in-place
  (testing "the page opens its dialogs by HTML alone"
    (multiple-value-bind (status body) (request :get "/")
      (ok (= status 200))
      (ok (search "commandfor=\"new-space\" command=\"show-modal\"" body))
      (ok (search "<dialog id=\"new-space\" closedby=\"any\"" body))))
  (testing "a space made answers a closed dialog, the list and a flash"
    (multiple-value-bind (status body) (call-action :post (create-space-action) :form '(("name" . "blog")))
      (ok (= status 200))
      (ok (search "<dialog id=\"new-space\"" body))
      (ng (search "<dialog id=\"new-space\" open" body))
      (ok (search "id=\"spaces\" hx-swap-oob=\"true\"" body))
      (ok (search "Space blog created." body)))
    (ok (find-space "blog")))
  (testing "a refused name stays in the open dialog"
    (multiple-value-bind (status body headers) (call-action :post (create-space-action) :form '(("name" . "blog")))
      (ok (= status 422))
      (ok (equal (getf headers :hx-retarget) "#new-space-error"))
      (ok (search "already exists" body))))
  (testing "deleting answers the list"
    (multiple-value-bind (status body) (call-action :post (delete-space-action) :form '(("name" . "blog")))
      (ok (= status 200))
      (ok (search "id=\"spaces\"" body))
      (ok (search "Space blog deleted." body)))
    (ng (find-space "blog"))
    (ok (= 404 (call-action :post (delete-space-action) :form '(("name" . "blog")))))))
