(defpackage #:koya-tests/server/web/api-support
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/schema/deploy #:replace-schema)
  (:import-from #:koya-server/web/app #:app)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:exec)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:create-space)
  (:import-from #:koya-server/usecases/ports/keys #:create-delivery-key #:create-management-key)
  (:import-from #:koya-server/usecases/webhooks/notify #:*webhook-async*)
  (:import-from #:koya-tests/server/fake-webhooks #:*webhook-sender*)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema #:make-webhook)
  (:import-from #:koya/core/json #:parse-json #:to-json #:jget)
  (:import-from #:alexandria #:alist-hash-table)
  (:import-from #:babel #:string-to-octets)
  (:import-from #:flexi-streams #:make-in-memory-input-stream)
  (:import-from #:koya-tests/server/usecases/media/library #:*media-root* #:multipart-body)
  (:export #:*secret* #:*management-key* #:*api-key* #:*webhooks* #:test-schema #:request #:admin #:admin-upload #:delivery #:webhook-events #:setup-api #:reset-api))
(in-package #:koya-tests/server/web/api-support)

;;; What every file of API tests shares: an in-memory instance with the website
;;; space and its keys, requests driven through the whole app, and the webhooks
;;; the app would have sent.

(defparameter *secret* "test-secret")

(defvar *management-key* nil "Created in SETUP; the Bearer token of every admin call.")

(defvar *api-key* nil)

(defvar *webhooks* '())

(defun test-schema ()
  (make-schema :webhooks (list (make-webhook "hook" "https://example.com/hook"))
               :models (list (make-model "blog" :list (list (make-field :title :text :required t :unique t)
                                                            (make-field :body :richtext)
                                                            (make-field :featured :boolean :default t)
                                                            (make-field :tags :reference :model "tag" :many t)
                                                            (make-field :cover :media)))
                             (make-model "tag" :list (list (make-field :name :text :required t)))
                             (make-model "about" :object (list (make-field :body :richtext))))))

(defun request (method path &key query body headers)
  "Call the app with a synthetic Lack env. Returns (values status parsed-json raw-body)."
  (let* ((env (list :request-method method :script-name "" :path-info path :query-string (or query "")
                    :server-name "localhost" :server-port 3000 :server-protocol :http/1.1
                    :request-uri (format nil "~a~@[?~a~]" path query) :url-scheme "http" :remote-addr "127.0.0.1"
                    :headers (alist-hash-table headers :test 'equal)
                    :content-type nil :content-length nil :raw-body nil)))
    (when body
      (let ((octets (string-to-octets (to-json body) :encoding :utf-8)))
        (setf (getf env :content-type) "application/json"
              (getf env :content-length) (length octets)
              (getf env :raw-body) (make-in-memory-input-stream octets))))
    (destructuring-bind (status response-headers body) (funcall (app) env)
      (if (pathnamep body)
          ;; a file response (see *media-middleware*): hand back the headers and the path
          (values status response-headers body)
          (let ((text (apply #'concatenate 'string (if (listp body) body (list body)))))
            (values status (and (plusp (length text)) (ignore-errors (parse-json text))) text))))))

(defun admin (method path &key body query)
  (request method path :query query :body body
                       :headers `(("authorization" . ,(format nil "Bearer ~a" *management-key*)))))

(defun admin-upload (path parts)
  "POST a multipart body as the owner. Returns (values status json)."
  (multiple-value-bind (octets content-type) (multipart-body parts)
    (let ((env (list :request-method :post :script-name "" :path-info path :query-string ""
                     :server-name "localhost" :server-port 3000 :server-protocol :http/1.1
                     :request-uri path :url-scheme "http" :remote-addr "127.0.0.1"
                     :headers (alist-hash-table `(("authorization" . ,(format nil "Bearer ~a" *management-key*))) :test 'equal)
                     :content-type content-type :content-length (length octets)
                     :raw-body (make-in-memory-input-stream octets))))
      (destructuring-bind (status headers body) (funcall (app) env)
        (declare (ignore headers))
        (let ((text (apply #'concatenate 'string (if (listp body) body (list body)))))
          (values status (and (plusp (length text)) (ignore-errors (parse-json text)))))))))

(defun delivery (path &key query (key *api-key*))
  (request :get path :query query :headers (and key `(("x-koya-delivery-key" . ,key)))))

(defun webhook-events () (mapcar (lambda (w) (jget (second w) "event")) (reverse *webhooks*)))

(defun setup-api ()
  "A fresh in-memory instance with the website space, its keys, and a webhook
sender that records instead of sending, for one file of API tests."
  (setf (uiop:getenv "KOYA_SECRET") *secret*)
  (setf (uiop:getenv "KOYA_BASE_URL") "http://localhost:3000")
  (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring *media-root*))
  (connect-db ":memory:")
  (migrate)
  (create-space "website")
  (create-space "other")
  (replace-schema "website" (test-schema))
  (setf *api-key* (create-delivery-key "website" :label "test"))
  (setf *management-key* (create-management-key "website" :label "test"))
  (setf *webhook-async* nil)
  (setf *webhook-sender* (lambda (url payload headers)
                           (push (list url (parse-json payload) headers) *webhooks*)
                           (values 200 "{\"revalidated\":true}" nil))))

(defun reset-api ()
  "Before each test: no contents, no delivery log, nothing sent."
  (exec "DELETE FROM contents")
  (exec "DELETE FROM webhook_deliveries")
  (setf *webhooks* '()))
