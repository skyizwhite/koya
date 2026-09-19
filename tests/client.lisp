(defpackage #:koya-tests/client
  (:use #:cl #:rove)
  (:import-from #:koya-server #:start #:stop)
  (:import-from #:koya-server/db/api-keys #:create-api-key)
  (:import-from #:koya-server/lib/webhook #:*webhook-sender* #:*webhook-async*)
  (:import-from #:koya/config #:defspace #:defmodel #:clear-schema #:current-schema)
  (:import-from #:koya/core/schema #:schema-spaces #:space-name #:space-models #:model-name)
  (:import-from #:koya/client
                #:configure #:koya-error #:koya-error-status #:koya-error-code
                #:pull #:get-list #:get-item #:get-object
                #:list-contents #:get-content #:create-content #:update-content
                #:publish-content #:unpublish-content #:delete-content #:draft-key
                #:list-api-keys #:delete-api-key #:webhook-secret))
(in-package #:koya-tests/client)

(defparameter *port* 3987)
(defparameter *secret* "client-test-secret")

(setup
  (setf (uiop:getenv "KOYA_SECRET") *secret*)
  (setf *webhook-async* nil)
  (setf *webhook-sender* (lambda (url payload headers) (declare (ignore url payload headers))))
  (start :server :woo :port *port* :db ":memory:")
  (configure :base-url (format nil "http://127.0.0.1:~a" *port*) :secret *secret* :space "website")
  (clear-schema)
  (defspace website)
  (defmodel (website blog) ()
    (title :text :required t)
    (body :richtext)
    (tags :reference :model tag :many t))
  (defmodel (website tag) ()
    (name :text :required t))
  (defmodel (website about) (:kind :object)
    (body :richtext)))

(teardown
  (stop)
  (clear-schema))

(deftest deploy-plan-pull
  (let ((changes (koya/client:plan :stream (make-broadcast-stream))))
    (ok (= (length changes) 9) "everything is new"))
  (let ((applied (koya/client:deploy :stream (make-broadcast-stream))))
    (ok (= (length applied) 9)))
  (ok (null (koya/client:plan :stream (make-broadcast-stream))) "nothing left to change")
  (let ((remote (pull)))
    (ok (equal (mapcar #'model-name (space-models (first (schema-spaces remote)))) '("blog" "tag" "about"))))
  (testing "destructive push without confirmation is refused"
    (clear-schema)
    (defspace website)
    (defmodel (website blog) () (title :text :required t))
    (ok (null (koya/client:deploy :confirm nil :stream (make-broadcast-stream))))
    (ok (= (length (space-models (first (schema-spaces (pull))))) 3) "untouched")
    (ok (koya/client:deploy :force t :stream (make-broadcast-stream)))
    (ok (= (length (space-models (first (schema-spaces (pull))))) 1))
    ;; restore
    (defmodel (website blog) () (title :text :required t) (body :richtext) (tags :reference :model tag :many t))
    (defmodel (website tag) () (name :text :required t))
    (defmodel (website about) (:kind :object) (body :richtext))
    (koya/client:deploy :force t :stream (make-broadcast-stream))))

(deftest contents-and-delivery
  (configure :api-key (create-api-key "website" :label "client"))
  (let* ((tag (create-content 'tag '(:name "lisp") :publish t))
         (post (create-content 'blog (list :title "Hello" :body "# Hi" :tags (list (getf tag :id))))))
    (ok (string= (getf tag :status) "published"))
    (ok (string= (getf post :status) "draft"))
    (ok (null (getf (get-list 'blog) :contents)) "draft not delivered")
    (let ((published (publish-content 'blog (getf post :id))))
      (ok (string= (getf published :status) "published"))
      (ok (string= (getf (getf published :published) :body) "# Hi")))
    (let ((list (get-list 'blog :query '(:limit 5 :orders "-publishedAt"))))
      (ok (= (getf list :total-count) 1))
      (ok (= (getf list :limit) 5))
      (let ((item (first (getf list :contents))))
        (ok (string= (getf item :title) "Hello"))
        (ok (string= (getf (first (getf item :tags)) :name) "lisp") "references expanded into plists")
        (ok (getf item :published-at))))
    (let ((item (get-item 'blog (getf post :id) :query '(:fields "id,title"))))
      (ok (equal (sort (loop :for k :in item :by #'cddr :collect k) #'string<) '(:id :title))))
    (testing "drafts and preview"
      (update-content 'blog (getf post :id) '(:title "Hello v2"))
      (ok (string= (getf (get-item 'blog (getf post :id)) :title) "Hello"))
      (let ((key (draft-key 'blog (getf post :id))))
        (ok (string= (getf (get-item 'blog (getf post :id) :query (list :draft-key key)) :title) "Hello v2")))
      (ok (string= (getf (get-content 'blog (getf post :id)) :status) "published+draft"))
      (ok (= (getf (list-contents 'blog) :total-count) 1)))
    (testing "object model"
      (create-content 'about '(:body "about") :publish t)
      (ok (string= (getf (get-object 'about) :body) "about")))
    (testing "errors become koya-error"
      (let ((e (handler-case (get-item 'blog "01ARZ3NDEKTSV4RRFFQ69G5FAV") (koya-error (e) e))))
        (ok (= (koya-error-status e) 404))
        (ok (string= (koya-error-code e) "not_found")))
      (let ((e (handler-case (create-content 'blog '(:body "no title")) (koya-error (e) e))))
        (ok (= (koya-error-status e) 422))
        (ok (string= (koya-error-code e) "validation_failed"))))
    (testing "unpublish and delete"
      (ok (string= (getf (unpublish-content 'blog (getf post :id)) :status) "draft"))
      (ok (getf (delete-content 'blog (getf post :id)) :deleted))
      (ok (= (getf (list-contents 'blog) :total-count) 0)))
    (testing "import with explicit id and date"
      (let ((imported (create-content 'tag '(:name "imported") :publish t :id "abc123" :published-at "2025-01-02T03:04:05.000Z")))
        (ok (string= (getf imported :id) "abc123"))
        (ok (string= (getf imported :published-at) "2025-01-02T03:04:05.000Z"))
        (ok (string= (getf (get-item 'tag "abc123") :name) "imported"))))
    (testing "webhook secret"
      (ok (= (length (webhook-secret)) 48)))
    (testing "api keys"
      (ok (= (length (list-api-keys)) 1))
      (multiple-value-bind (key id) (koya/client:create-api-key :label "extra")
        (ok (stringp key))
        (ok (= (length (list-api-keys)) 2))
        (delete-api-key id)
        (ok (= (length (list-api-keys)) 1))))))
