(defpackage #:koya-tests/server/pages/support
  (:use #:cl #:rove)
  (:import-from #:koya-server/app #:*app*)
  (:import-from #:koya-server/pages/s/<space>/m/<model>/<id> #:editor-action)
  (:import-from #:koya-server/db/connection #:connect-db)
  (:import-from #:koya-server/db/migrations #:migrate)
  (:import-from #:koya-server/db/schema-store #:save-schema #:create-space)
  (:import-from #:koya-tests/server/features/media/store #:*media-root* #:multipart-body)
  (:import-from #:koya-server/features/webhooks/notify #:*webhook-sender* #:*webhook-async*)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:alexandria #:alist-hash-table)
  (:import-from #:babel #:string-to-octets)
  (:import-from #:flexi-streams #:make-in-memory-input-stream)
  (:import-from #:quri #:url-encode-params)
  (:export #:*secret* #:*cookie* #:*set-cookie* #:blog-model #:request #:location #:request-url #:call-action #:edit #:moved-to #:post-login #:setup-pages #:log-in))
(in-package #:koya-tests/server/pages/support)

;;; What every file of page tests shares: an in-memory instance with the website
;;; space, and requests driven through the whole app with the owner's cookie.

(defparameter *secret* "ui-secret")

(defvar *cookie* nil)

(defvar *set-cookie* nil "The last Set-Cookie header seen, flags included.")

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

(defun request (method path &key form multipart json body content-type headers query)
  "Returns (values status body-string headers-plist). FORM is urlencoded; MULTIPART
is a list of parts for MULTIPART-BODY; JSON is a string sent as the body, for the
admin API, which the session reaches as well as a management key does."
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
    (destructuring-bind (status response-headers body) (funcall *app* env)
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
  "REQUEST with a URL that may carry a query string, e.g. an action endpoint."
  (let ((q (position #\? url)))
    (apply #'request method (subseq url 0 q) :query (and q (subseq url (1+ q))) args)))

(defun edit (path &key form headers)
  "Do to the content at PATH (/s/<space>/m/<model>/<id>) what the editor's button
named by FORM's \"action\" does (save when there is none), with the rest of FORM as
the editor's fields. (values status body headers)."
  (destructuring-bind (s space m model id) (rest (uiop:split-string path :separator "/"))
    (declare (ignore s m))
    (call-action :post (editor-action :space space :model model :id id
                                      :op (or (cdr (assoc "action" form :test #'equal)) "save"))
                 :form (remove "action" form :key #'car :test #'equal)
                 :headers headers)))

(defun moved-to (headers)
  "Where an action's answer sends the browser: another page, or this one's URL cleaned."
  (or (getf headers :hx-redirect) (getf headers :hx-replace-url)))

(defun call-action (method url &rest args &key headers &allow-other-keys)
  "Call an action as htmx does: from this server's origin, with HX-Request. HEADERS
override those: the first of a name is the one the table keeps."
  (apply #'request-url method url
         :headers (append headers '(("hx-request" . "true") ("origin" . "http://localhost:3000")))
         (loop :for (k v) :on args :by #'cddr :unless (eq k :headers) :append (list k v))))

(defun setup-pages ()
  "A fresh in-memory instance with the website space, for one file of page tests."
  (setf (uiop:getenv "KOYA_SECRET") *secret*)
  (setf (uiop:getenv "KOYA_BASE_URL") "http://localhost:3000")
  (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring *media-root*))
  (setf *webhook-async* nil)
  (setf *webhook-sender* (lambda (url payload headers) (declare (ignore url payload headers))))
  (connect-db ":memory:")
  (migrate)
  (create-space "website")
  (save-schema "website"
               (make-schema :models (list (blog-model)
                                          (make-model "about" :object (list (make-field :body :richtext)))))))

(defun post-login (&rest args &key form headers)
  "Send the login form as the page does. (values status body headers)."
  (declare (ignore form headers))
  ;; named in full: LOG-IN here is the tests' own
  (apply #'call-action :post (koya-server/pages/login:log-in) args))

(defun log-in ()
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*))))
