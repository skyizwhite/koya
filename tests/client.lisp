(defpackage #:koya-tests/client
  (:use #:cl #:rove)
  (:import-from #:koya-server #:start #:stop)
  (:import-from #:koya-server/db/api-keys #:create-api-key)
  (:import-from #:koya-server/db/management-keys #:create-management-key)
  (:import-from #:koya-server/lib/webhook #:*webhook-sender* #:*webhook-async*)
  (:import-from #:koya-server/db/schema-store #:create-space)
  (:import-from #:koya/config #:defmodel #:clear-schema #:current-schema)
  (:import-from #:koya/core/schema #:schema-models #:model-name)
  (:import-from #:koya/client
                #:configure #:koya-error #:koya-error-status #:koya-error-code
                #:pull #:get-list #:get-item #:get-object
                #:list-contents #:get-content #:create-content #:update-content
                #:publish-content #:unpublish-content #:discard-draft #:delete-content #:draft-key
                #:list-api-keys #:delete-api-key #:webhook-secret
                #:list-media #:get-media #:upload-media #:update-media #:delete-media)
  (:import-from #:koya-tests/server/media #:png-bytes #:*media-root*))
(in-package #:koya-tests/client)

(defparameter *port* 3987)
(defparameter *secret* "client-test-secret")

(setup
  (setf (uiop:getenv "KOYA_SECRET") *secret*)
  (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring *media-root*))
  (setf *webhook-async* nil)
  (setf *webhook-sender* (lambda (url payload headers) (declare (ignore url payload headers))))
  (start :server :woo :port *port* :db ":memory:")
  ;; the space is made here, as the admin UI would: a deploy never creates one
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
  (let ((changes (koya/client:plan :stream (make-broadcast-stream))))
    (ok (= (length changes) 9) "everything is new"))
  (let ((applied (koya/client:deploy :stream (make-broadcast-stream))))
    (ok (= (length applied) 9)))
  (ok (null (koya/client:plan :stream (make-broadcast-stream))) "nothing left to change")
  (let ((remote (pull)))
    (ok (equal (mapcar #'model-name (schema-models remote)) '("blog" "tag" "about"))))
  (testing "a management key reaches its own space and no other"
    (let ((e (handler-case (pull :space "other") (koya-error (e) e))))
      (ok (= (koya-error-status e) 403))
      (ok (string= (koya-error-code e) "forbidden"))))
  (testing "destructive push without confirmation is refused"
    (clear-schema)
    (defmodel blog (:kind :list) (title :text :required t))
    (ok (null (koya/client:deploy :confirm nil :stream (make-broadcast-stream))))
    (ok (= (length (schema-models (pull))) 3) "untouched")
    (ok (koya/client:deploy :force t :stream (make-broadcast-stream)))
    (ok (= (length (schema-models (pull))) 1))
    ;; restore
    (defmodel blog (:kind :list) (title :text :required t) (body :richtext) (tags :reference :model tag :many t) (cover :media))
    (defmodel tag (:kind :list) (name :text :required t))
    (defmodel about (:kind :object) (body :richtext))
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
    (let ((list (get-list 'blog :query '(:limit 5 :orders "-publishedAt" :include ("tags")))))
      (ok (= (getf list :total-count) 1))
      (ok (= (getf list :limit) 5))
      (let ((item (first (getf list :contents))))
        (ok (string= (getf item :title) "Hello"))
        (ok (string= (getf (first (getf item :tags)) :name) "lisp") "included references expand into plists")
        (ok (getf item :published-at))))
    (ok (stringp (first (getf (get-item 'blog (getf post :id)) :tags))) "references are ids by default")
    (let ((item (get-item 'blog (getf post :id) :query '(:fields "id,title"))))
      (ok (equal (sort (loop :for k :in item :by #'cddr :collect k) #'string<) '(:id :title))))
    (testing "an unpublished draft previews with a nil publishedAt"
      (let* ((draft (create-content 'blog '(:title "Only a draft")))
             (item (get-item 'blog (getf draft :id) :query (list :draft-key (getf draft :draft-key)))))
        (ok (string= (getf item :title) "Only a draft"))
        (ok (member :published-at item) "key is present")
        (ok (null (getf item :published-at)) "but nil, not the null symbol")
        (delete-content 'blog (getf draft :id))))
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
    (testing "discard a draft"
      (ok (string= (getf (update-content 'blog (getf post :id) '(:title "Scratch")) :status) "published+draft"))
      (ok (string= (getf (discard-draft 'blog (getf post :id)) :status) "published")))
    (testing "unpublish and delete"
      (ok (string= (getf (unpublish-content 'blog (getf post :id)) :status) "draft"))
      (ok (getf (delete-content 'blog (getf post :id)) :deleted))
      (ok (= (getf (list-contents 'blog) :total-count) 0)))
    (testing "import with explicit id and dates"
      (let ((imported (create-content 'tag '(:name "imported") :publish t :id "abc123"
                                      :created-at "2024-12-31T00:00:00.000Z"
                                      :updated-at "2025-01-03T00:00:00.000Z"
                                      :published-at "2025-01-02T03:04:05.000Z"
                                      :revised-at "2025-01-02T04:00:00.000Z")))
        (ok (string= (getf imported :id) "abc123"))
        (ok (string= (getf imported :created-at) "2024-12-31T00:00:00.000Z"))
        (ok (string= (getf imported :updated-at) "2025-01-03T00:00:00.000Z"))
        (ok (string= (getf imported :published-at) "2025-01-02T03:04:05.000Z"))
        (ok (string= (getf imported :revised-at) "2025-01-02T04:00:00.000Z"))
        (ok (string= (getf (get-item 'tag "abc123") :name) "imported")))
      (ok (signals (create-content 'tag '(:name "bad date") :created-at "yesterday") 'koya-error)
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
          (let ((post (create-content 'blog (list :title "Covered" :cover (getf media :id)) :publish t)))
            (ok (string= (getf (getf (get-item 'blog (getf post :id)) :cover) :alt) "Changed")
                "delivery expands :media into a plist")
            (ok (= (getf (get-media (getf media :id)) :references) 1))
            (delete-content 'blog (getf post :id)))
          (ok (getf (delete-media (getf media :id)) :deleted))
          (ok (= (getf (list-media) :total-count) 0)))))
    (testing "api keys"
      (ok (= (length (list-api-keys)) 1))
      (multiple-value-bind (key id) (koya/client:create-api-key :label "extra")
        (ok (stringp key))
        (ok (= (length (list-api-keys)) 2))
        (delete-api-key id)
        (ok (= (length (list-api-keys)) 1))))))
