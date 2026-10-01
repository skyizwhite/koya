(defpackage #:koya-spec/server/web/pages/index
  (:use #:cl #:rove)
  (:import-from #:koya-spec/server/web/pages/support
                #:request #:call-action #:setup-pages #:log-in)
  (:import-from #:koya-server/web/pages/index #:create-space-action #:delete-space-action)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-server/usecases/ports/spaces #:find-space)
  (:import-from #:koya-server/usecases/keys
                #:create-delivery-key #:list-delivery-keys #:create-management-key
                #:list-management-keys))
(in-package #:koya-spec/server/web/pages/index)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest spaces-page
  (multiple-value-bind (status body) (request :get "/")
    (ok (= status 200))
    (ok (search "<html lang=\"en\"" body) "the admin UI is in English")
    (ok (search "website" body))
    (ok (search "commandfor=\"new-space\"" body) "the form is behind a button")
    (ok (search "<dialog id=\"new-space\"" body) "and lives in a dialog on the page")
    (ok (search (format nil "data-post=\"~a\" nm-bind=\"{ onsubmit: koya.submit }\"" (create-space-action)) body)))
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
    (ok (= 200 (call-action :post (delete-space-action)
                            :form '(("name" . "shop") ("confirm" . "delete shop")))))
    (ng (find-space "shop"))
    (ok (null (list-delivery-keys "shop")))
    (ok (null (list-management-keys "shop")))
    (ok (= 404 (request :get "/s/shop"))))
  (testing "an unknown space cannot be deleted"
    (ok (= 404 (call-action :post (delete-space-action)
                            :form '(("name" . "ghost") ("confirm" . "delete ghost"))))))
  (testing "the page takes no posts: what is done here is an action"
    (ok (= 404 (request :post "/" :form '(("name" . "shop")) :headers '(("origin" . "http://localhost:3000")))))))

(deftest spaces-are-made-and-deleted-in-place
  (testing "the page opens its dialogs by HTML alone"
    (multiple-value-bind (status body) (request :get "/")
      (ok (= status 200))
      (ok (search "commandfor=\"new-space\" command=\"show-modal\"" body))
      (ok (search "<dialog id=\"new-space\" closedby=\"any\"" body))
      (ok (search "pattern=\"[a-z][a-z0-9\\-]*\"" body)
          "the hyphen escaped, as a pattern read with the v flag needs")))
  (testing "a space made answers a closed dialog, the list and a toast"
    (multiple-value-bind (status body) (call-action :post (create-space-action) :form '(("name" . "blog")))
      (ok (= status 200))
      (ok (search "<dialog id=\"new-space\"" body))
      (ng (search "<dialog id=\"new-space\" open" body))
      (ok (search "<div id=\"spaces\">" body))
      (ok (search "Space blog created." body)))
    (ok (find-space "blog")))
  (testing "a refused name stays in the open dialog"
    (multiple-value-bind (status body) (call-action :post (create-space-action) :form '(("name" . "blog")))
      (ok (= status 422))
      (ok (search "<p id=\"new-space-error\"" body) "the dialog's error line, drawn again")
      (ng (search "<dialog" body) "and the dialog left as it is")
      (ok (search "already exists" body))))
  (testing "deleting is behind a dialog asking for the space's name to be typed"
    (let ((body (nth-value 1 (request :get "/"))))
      (ok (search "commandfor=\"delete-space-blog\" command=\"show-modal\"" body))
      (ok (search "<dialog id=\"delete-space-blog\" closedby=\"any\"" body))
      (ok (search "<dialog id=\"delete-space-blog\" closedby=\"any\" class=\"koya-dialog max-w-sm\" nm-data=\"...koya.phrase(this)\"" body)
          "the dialog holds what is typed")
      (ok (search "data-confirm-phrase=\"delete blog\"" body))
      (ok (search "<input type=\"text\" id=\"delete-phrase-blog\"" body))
      (ok (search "type=\"submit\" class=\"btn btn-danger\" disabled" body)
          "its button waits for the phrase")))
  (testing "a missing or wrong phrase deletes nothing"
    (dolist (confirm '(nil "delete" "Delete blog" "delete blog " "delete shop"))
      (ok (= 422 (call-action :post (delete-space-action)
                              :form (list* '("name" . "blog") (and confirm `(("confirm" . ,confirm)))))))
      (ok (find-space "blog"))))
  (testing "and says why in the open dialog, where a toast would be hidden"
    (multiple-value-bind (status body)
        (call-action :post (delete-space-action) :form '(("name" . "blog") ("confirm" . "delete")))
      (ok (= status 422))
      (ok (search "<p id=\"delete-error-blog\"" body))
      (ng (search "<dialog" body))
      (ok (search "Type &quot;delete blog&quot; to delete this space." body)))
    (multiple-value-bind (status body)
        (call-action :post (delete-space-action) :form '(("name" . "ghost") ("confirm" . "delete ghost")))
      (ok (= status 404))
      (ok (search "<p id=\"delete-error-ghost\"" body))
      (ok (search "Space not found." body))))
  (testing "deleting answers the list"
    (multiple-value-bind (status body)
        (call-action :post (delete-space-action) :form '(("name" . "blog") ("confirm" . "delete blog")))
      (ok (= status 200))
      (ok (search "id=\"spaces\"" body))
      (ok (search "Space blog deleted." body)))
    (ng (find-space "blog"))
    (ok (= 404 (call-action :post (delete-space-action)
                            :form '(("name" . "blog") ("confirm" . "delete blog")))))))

(defun ids-in (html)
  (loop :with marker := " id=\""
        :for start := (search marker html) :then (search marker html :start2 end)
        :for end := (and start (position #\" html :start (+ start (length marker))))
        :while end
        :collect (subseq html (+ start (length marker)) end)))

(deftest no-space-takes-another-spaces-ids
  (let ((names '("shop" "shop-error" "shop-phrase" "error-shop" "phrase-shop" "space-shop")))
    (dolist (name names)
      (call-action :post (create-space-action) :form `(("name" . ,name))))
    (let ((ids (ids-in (nth-value 1 (request :get "/")))))
      (ok (every (lambda (name) (find (format nil "delete-space-~a" name) ids :test #'string=)) names))
      (ok (= (length ids) (length (remove-duplicates ids :test #'string=)))
          "a name ending or starting like another's ids takes none of them"))
    (dolist (name names)
      (call-action :post (delete-space-action) :form `(("name" . ,name) ("confirm" . ,(format nil "delete ~a" name)))))))
