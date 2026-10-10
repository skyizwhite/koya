(defpackage #:koya-spec/sdk/client
  (:use #:cl #:rove)
  (:import-from #:koya-server #:start #:stop)
  (:import-from #:koya-server/usecases/keys #:create-delivery-key #:create-management-key)
  (:import-from #:koya-server/usecases/webhooks #:*webhook-async*)
  (:import-from #:koya-spec/server/fake-webhooks #:*webhook-sender*)
  (:import-from #:koya-server/usecases/spaces #:create-space)
  (:import-from #:koya-sdk/config #:defmodel #:clear-schema)
  (:import-from #:koya-core/schema #:schema-models #:model-name)
  (:import-from #:koya-sdk/client
                #:configure #:koya-error #:koya-error-status #:koya-error-code #:pull #:get-list
                #:get-list-content #:get-object #:admin-get-list #:admin-get-list-content
                #:admin-create-list-content #:admin-update-list-content #:admin-publish-list-content
                #:admin-unpublish-list-content #:admin-discard-list-content-draft
                #:admin-delete-list-content #:admin-list-content-draft-key #:list-delivery-keys
                #:delete-delivery-key #:webhook-secret #:list-media #:get-media #:upload-media
                #:update-media #:delete-media #:deploy #:admin-get-object #:admin-update-object
                #:admin-publish-object #:admin-unpublish-object #:admin-discard-object-draft
                #:admin-object-draft-key)
  (:import-from #:koya-spec/server/usecases/media #:png-bytes #:*media-root*)
  (:import-from #:usocket #:socket-connect #:socket-close #:socket-error))
(in-package #:koya-spec/sdk/client)

(defparameter *port* 3987)
(defparameter *secret* "client-test-secret-long-enough-to-log-in")

(defun wait-for-server (port)
  (loop :repeat 200
        :do (handler-case (progn (socket-close (socket-connect "127.0.0.1" port))
                                 (return))
              (socket-error () (sleep 0.05)))
        :finally (error "Nothing listens on port ~a" port)))

(setup
  (setf (uiop:getenv "KOYA_SECRET") *secret*)
  (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring *media-root*))
  (setf (uiop:getenv "KOYA_BASE_URL") (format nil "http://127.0.0.1:~a" *port*))
  (setf *webhook-async* nil)
  (setf *webhook-sender* (lambda (url payload headers) (declare (ignore url payload headers))))
  (start :server :woo :port *port* :db ":memory:")
  (wait-for-server *port*)
  (create-space "website")
  (configure :base-url (format nil "http://127.0.0.1:~a" *port*)
             :management-key (create-management-key "website" :label "client")
             :space "website")
  (clear-schema)
  (defmodel blog (:kind :list)
    (title :text :required t)
    (body :richtext)
    (tags :reference :model tag :many t)
    (cover :media))
  (defmodel tag (:kind :list)
    (name :text :required t))
  (defmodel about (:kind :object)
    (body :richtext)))

(teardown
  (stop)
  (clear-schema))

(deftest deploy-plan-pull
  (let ((changes (koya-sdk/client:plan :stream (make-broadcast-stream))))
    (ok (= (length changes) 9) "everything is new"))
  (let ((applied (deploy :stream (make-broadcast-stream))))
    (ok (= (length applied) 9)))
  (ok (null (koya-sdk/client:plan :stream (make-broadcast-stream))) "nothing left to change")
  (let ((remote (pull)))
    (ok (equal (mapcar #'model-name (schema-models remote)) '("blog" "tag" "about"))))
  (testing "a management key reaches its own space and no other"
    (let ((e (handler-case (pull :space "other") (koya-error (e) e))))
      (ok (= (koya-error-status e) 403))
      (ok (string= (koya-error-code e) "forbidden"))))
  (testing "destructive push without confirmation is refused"
    (clear-schema)
    (defmodel blog (:kind :list) (title :text :required t))
    (ok (null (deploy :confirm nil :stream (make-broadcast-stream))))
    (ok (= (length (schema-models (pull))) 3) "untouched")
    (ok (deploy :force t :stream (make-broadcast-stream)))
    (ok (= (length (schema-models (pull))) 1))
    (defmodel blog (:kind :list) (title :text :required t) (body :richtext) (tags :reference :model tag :many t) (cover :media))
    (defmodel tag (:kind :list) (name :text :required t))
    (defmodel about (:kind :object) (body :richtext))
    (deploy :force t :stream (make-broadcast-stream))))

(deftest contents-and-delivery
  (configure :delivery-key (create-delivery-key "website" :label "client"))
  (let* ((tag (admin-create-list-content 'tag '(:name "lisp") :publish t))
         (post (admin-create-list-content 'blog (list :title "Hello" :body "# Hi" :tags (list (getf tag :id))))))
    (ok (string= (getf tag :status) "published"))
    (ok (string= (getf post :status) "draft"))
    (ok (null (getf (get-list 'blog) :contents)) "draft not delivered")
    (let ((published (admin-publish-list-content 'blog (getf post :id))))
      (ok (string= (getf published :status) "published"))
      (ok (string= (getf (getf published :published) :body) "# Hi")))
    (let ((list (get-list 'blog :query '(:limit 5 :orders "-publishedAt" :include ("tags")))))
      (ok (= (getf list :total-count) 1))
      (ok (= (getf list :limit) 5))
      (let ((item (first (getf list :contents))))
        (ok (string= (getf item :title) "Hello"))
        (ok (string= (getf (first (getf item :tags)) :name) "lisp") "included references expand into plists")
        (ok (getf item :published-at))))
    (ok (stringp (first (getf (get-list-content 'blog (getf post :id)) :tags))) "references are ids by default")
    (let ((item (get-list-content 'blog (getf post :id) :query '(:fields "title"))))
      (ok (equal (sort (loop :for k :in item :by #'cddr :collect k) #'string<)
                 '(:created-at :id :published-at :revised-at :title :updated-at))
          "fields narrows the data, and the system fields stay"))
    (testing "an unpublished draft previews with a nil publishedAt"
      (let* ((draft (admin-create-list-content 'blog '(:title "Only a draft")))
             (item (get-list-content 'blog (getf draft :id) :query (list :draft-key (getf draft :draft-key)))))
        (ok (string= (getf item :title) "Only a draft"))
        (ok (member :published-at item) "key is present")
        (ok (null (getf item :published-at)) "but nil, not the null symbol")
        (admin-delete-list-content 'blog (getf draft :id))))
    (testing "drafts and preview"
      (admin-update-list-content 'blog (getf post :id) '(:title "Hello v2"))
      (ok (string= (getf (get-list-content 'blog (getf post :id)) :title) "Hello"))
      (let ((key (admin-list-content-draft-key 'blog (getf post :id))))
        (ok (string= (getf (get-list-content 'blog (getf post :id) :query (list :draft-key key)) :title) "Hello v2")))
      (ok (string= (getf (admin-get-list-content 'blog (getf post :id)) :status) "published+draft"))
      (ok (= (getf (admin-get-list 'blog) :total-count) 1)))
    (testing "object model"
      (ok (string= (getf (admin-update-object 'about '(:body "about")) :status) "draft") "the first save makes its content")
      (ok (string= (getf (admin-publish-object 'about) :status) "published"))
      (ok (string= (getf (get-object 'about) :body) "about"))
      (admin-update-object 'about '(:body "about v2"))
      (ok (string= (getf (get-object 'about :query (list :draft-key (admin-object-draft-key 'about))) :body) "about v2"))
      (ok (string= (getf (admin-get-object 'about) :status) "published+draft"))
      (ok (string= (getf (admin-discard-object-draft 'about) :status) "published"))
      (ok (string= (getf (getf (admin-publish-object 'about :data '(:body "given")) :published) :body) "given"))
      (ok (string= (getf (admin-unpublish-object 'about) :status) "draft")))
    (testing "errors become koya-error"
      (let ((e (handler-case (get-list-content 'blog "01ARZ3NDEKTSV4RRFFQ69G5FAV") (koya-error (e) e))))
        (ok (= (koya-error-status e) 404))
        (ok (string= (koya-error-code e) "not_found")))
      (let ((e (handler-case (admin-create-list-content 'blog '(:body "no title")) (koya-error (e) e))))
        (ok (= (koya-error-status e) 422))
        (ok (string= (koya-error-code e) "validation_failed"))))
    (testing "discard a draft"
      (ok (string= (getf (admin-update-list-content 'blog (getf post :id) '(:title "Scratch")) :status) "published+draft"))
      (ok (string= (getf (admin-discard-list-content-draft 'blog (getf post :id)) :status) "published")))
    (testing "unpublish and delete"
      (ok (string= (getf (admin-unpublish-list-content 'blog (getf post :id)) :status) "draft"))
      (ok (getf (admin-delete-list-content 'blog (getf post :id)) :deleted))
      (ok (= (getf (admin-get-list 'blog) :total-count) 0)))
    (testing "import with explicit dates"
      (let ((imported (admin-create-list-content 'tag '(:name "imported") :publish t
                                      :created-at "2024-12-31T00:00:00.000Z"
                                      :updated-at "2025-01-03T00:00:00.000Z"
                                      :published-at "2025-01-02T03:04:05.000Z"
                                      :revised-at "2025-01-02T04:00:00.000Z")))
        (ok (string= (getf imported :created-at) "2024-12-31T00:00:00.000Z"))
        (ok (string= (getf imported :updated-at) "2025-01-03T00:00:00.000Z"))
        (ok (string= (getf imported :published-at) "2025-01-02T03:04:05.000Z"))
        (ok (string= (getf imported :revised-at) "2025-01-02T04:00:00.000Z"))
        (ok (string= (getf (get-list-content 'tag (getf imported :id)) :name) "imported")))
      (ok (signals (admin-create-list-content 'tag '(:name "bad date") :created-at "yesterday") 'koya-error)
          "a malformed timestamp is rejected"))
    (testing "webhook secret"
      (ok (= (length (webhook-secret)) 48)))
    (testing "media"
      (let ((file (merge-pathnames "client-upload.png" *media-root*)))
        (ensure-directories-exist file)
        (with-open-file (out file :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
          (write-sequence (png-bytes 6 4) out))
        (let ((media (upload-media file :alt "Uploaded")))
          (ok (string= (getf media :filename) "client-upload.png"))
          (ok (= (getf media :width) 6))
          (ok (search "/media/website/" (getf media :url)))
          (ok (= (getf (list-media) :total-count) 1))
          (ok (= (getf (get-media (getf media :id)) :references) 0))
          (ok (string= (getf (update-media (getf media :id) :alt "Changed") :alt) "Changed"))
          (let ((post (admin-create-list-content 'blog (list :title "Covered" :cover (getf media :id)) :publish t)))
            (ok (string= (getf (getf (get-list-content 'blog (getf post :id)) :cover) :alt) "Changed")
                "delivery expands :media into a plist")
            (ok (= (getf (get-media (getf media :id)) :references) 1))
            (admin-delete-list-content 'blog (getf post :id)))
          (ok (getf (delete-media (getf media :id)) :deleted))
          (ok (= (getf (list-media) :total-count) 0)))))
    (testing "delivery keys"
      (ok (= (length (list-delivery-keys)) 1))
      (multiple-value-bind (key id) (koya-sdk/client:create-delivery-key :label "extra")
        (ok (stringp key))
        (ok (= (length (list-delivery-keys)) 2))
        (delete-delivery-key id)
        (ok (= (length (list-delivery-keys)) 1))))))

(deftest a-missing-setting-names-its-variable
  (let ((saved (uiop:getenv "KOYA_URL"))
        (koya-sdk/client:*base-url* nil))
    (sb-posix:unsetenv "KOYA_URL")
    (unwind-protect
         (let ((message (handler-case (progn (get-list 'blog) nil)
                          (error (e) (princ-to-string e)))))
           (ok (search "set koya-sdk:*base-url* or KOYA_URL" message)
               "the message names the variable to set, not its value"))
      (when saved (setf (uiop:getenv "KOYA_URL") saved)))))
