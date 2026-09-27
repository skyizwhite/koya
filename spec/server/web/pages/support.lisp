(defpackage #:koya-spec/server/web/pages/support
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/schema #:replace-schema)
  (:import-from #:koya-server/web/app #:app)
  (:import-from #:koya-server/web/pages/s/<space>/m/<model>/<id> #:editor-action)
  (:import-from #:koya-server/infra/db/connection #:connect-db)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/usecases/spaces #:create-space)
  (:import-from #:koya-spec/server/usecases/media #:*media-root* #:multipart-body)
  (:import-from #:koya-server/usecases/webhooks #:*webhook-async*)
  (:import-from #:koya-spec/server/fake-webhooks #:*webhook-sender*)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:alexandria #:alist-hash-table)
  (:import-from #:babel #:string-to-octets)
  (:import-from #:flexi-streams #:make-in-memory-input-stream)
  (:import-from #:quri #:url-encode-params)
  (:export #:*secret* #:*cookie* #:*set-cookie* #:blog-model #:request #:location #:request-url #:call-action #:edit #:moved-to #:post-login #:setup-pages #:log-in))
(in-package #:koya-spec/server/web/pages/support)

(defparameter *secret* "ui-secret-long-enough-to-log-in-with-it")

(defvar *cookie* nil)

(defvar *set-cookie* nil)

(defun blog-model ()
  (make-model "blog" :list (list (make-field :title :text :required t)
                                 (make-field :slug :slug :from :title :unique t)
                                 (make-field :body :richtext)
                                 (make-field :featured :boolean)
                                 (make-field :category :select :options '("news" "tech"))
                                 (make-field :labels :select :options '("a" "b") :many t)
                                 (make-field :count :number)
                                 (make-field :when :datetime)
                                 (make-field :cover :media)
                                 (make-field :related :reference :model "blog" :many t))
              :label :title
              :preview-url "https://site.test/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}"
              :public-url "https://site.test/blog/{CONTENT_ID}"))

(defun answer (response)
  (if (functionp response)
      (let (answer)
        (funcall response
                 (lambda (res)
                   (destructuring-bind (status headers &optional body) res
                     (setf answer (list status headers
                                        (if (pathnamep body)
                                            (alexandria:read-file-into-byte-vector body)
                                            body))))))
        answer)
      response))

(defun request (method path &key form multipart json body content-type headers query)
  (let* ((env (list :request-method method :script-name "" :path-info path :query-string (or query "")
                    :server-name "localhost" :server-port 3000 :server-protocol :http/1.1
                    :request-uri (format nil "~a~@[?~a~]" path query)
                    :url-scheme "http" :remote-addr "127.0.0.1"
                    :headers (alist-hash-table (append headers (and *cookie* (list (cons "cookie" *cookie*)))
                                                       (list (cons "host" "localhost:3000")))
                                               :test 'equal)
                    :content-type nil :content-length nil :raw-body nil)))
    (when form
      (let ((octets (string-to-octets (url-encode-params form) :encoding :utf-8)))
        (setf (getf env :content-type) "application/x-www-form-urlencoded"
              (getf env :content-length) (length octets)
              (getf env :raw-body) (make-in-memory-input-stream octets))))
    (when multipart
      (multiple-value-bind (octets content-type) (multipart-body multipart)
        (setf (getf env :content-type) content-type
              (getf env :content-length) (length octets)
              (getf env :raw-body) (make-in-memory-input-stream octets))))
    (when body
      (setf (getf env :content-type) content-type
            (getf env :content-length) (length body)
            (getf env :raw-body) (make-in-memory-input-stream body)))
    (when json
      (let ((octets (string-to-octets json :encoding :utf-8)))
        (setf (getf env :content-type) "application/json"
              (getf env :content-length) (length octets)
              (getf env :raw-body) (make-in-memory-input-stream octets))))
    (destructuring-bind (status response-headers body) (answer (funcall (app) env))
      (let ((set-cookie (getf response-headers :set-cookie)))
        (when set-cookie
          (setf *set-cookie* set-cookie
                *cookie* (subseq set-cookie 0 (position #\; set-cookie)))))
      (values status
              (cond ((pathnamep body) "")
                    ((typep body '(vector (unsigned-byte 8))) body)
                    (t (apply #'concatenate 'string (if (listp body) body (list body)))))
              response-headers))))

(defun location (headers) (getf headers :location))

(defun request-url (method url &rest args)
  (let ((q (position #\? url)))
    (apply #'request method (subseq url 0 q) :query (and q (subseq url (1+ q))) args)))

(defun edit (path &key form headers)
  (destructuring-bind (s space m model id) (rest (uiop:split-string path :separator "/"))
    (declare (ignore s m))
    (call-action :post (editor-action :space space :model model :id id
                                      :op (or (cdr (assoc "action" form :test #'equal)) "save"))
                 :form (remove "action" form :key #'car :test #'equal)
                 :headers headers)))

(defun moved-to (headers)
  (or (getf headers :hx-redirect) (getf headers :hx-replace-url)))

(defun call-action (method url &rest args &key headers &allow-other-keys)
  (apply #'request-url method url
         :headers (append headers '(("hx-request" . "true") ("origin" . "http://localhost:3000")))
         (loop :for (k v) :on args :by #'cddr :unless (eq k :headers) :append (list k v))))

(defun setup-pages ()
  (setf (uiop:getenv "KOYA_SECRET") *secret*)
  (setf (uiop:getenv "KOYA_BASE_URL") "http://localhost:3000")
  (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring *media-root*))
  (setf (uiop:getenv "KOYA_DB_PATH") (namestring (merge-pathnames "koya.db" *media-root*)))
  (setf *webhook-async* nil)
  (setf *webhook-sender* (lambda (url payload headers) (declare (ignore url payload headers))))
  (connect-db ":memory:")
  (migrate)
  (create-space "website")
  (replace-schema "website"
               (make-schema :models (list (blog-model)
                                          (make-model "about" :object (list (make-field :body :richtext)))))))

(defun post-login (&rest args &key form headers)
  (declare (ignore form headers))
  (apply #'call-action :post (koya-server/web/pages/login:log-in) args))

(defun log-in ()
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*))))
