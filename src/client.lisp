(defpackage #:koya/client
  (:use #:cl)
  (:import-from #:koya/core/json
                #:parse-json #:to-json #:jobject #:jget #:json-null)
  (:import-from #:koya/core/case
                #:camel-key #:jvalue->lisp #:lisp->jvalue)
  (:import-from #:koya/core/schema
                #:schema->jobject #:jobject->schema)
  (:import-from #:koya/core/diff
                #:format-change)
  (:import-from #:koya/config
                #:current-schema)
  (:import-from #:dexador)
  (:import-from #:quri
                #:make-uri #:render-uri)
  (:export #:*base-url* #:*secret* #:*api-key* #:*space*
           #:configure
           #:koya-error #:koya-error-status #:koya-error-code #:koya-error-message #:koya-error-details
           #:plan #:deploy #:pull
           #:get-list #:get-item #:get-object
           #:list-contents #:get-content #:create-content #:update-content
           #:publish-content #:unpublish-content #:delete-content #:draft-key
           #:create-api-key #:list-api-keys #:delete-api-key #:webhook-secret
           #:list-media #:get-media #:upload-media #:update-media #:delete-media))
(in-package #:koya/client)

;;; HTTP client for a koya server. Delivery calls need *API-KEY*; admin calls
;;; (schema push, content management, keys) need *SECRET*. Responses are
;;; converted to kebab-case keyword plists, arrays to lists.

(defvar *base-url* nil "Server URL, e.g. https://cms.example.com. Falls back to KOYA_URL.")
(defvar *secret* nil "Owner secret for admin calls. Falls back to KOYA_SECRET.")
(defvar *api-key* nil "Delivery API key. Falls back to KOYA_API_KEY.")
(defvar *space* nil "Default space for content calls. Falls back to KOYA_SPACE.")

(defun configure (&key base-url secret api-key space)
  (when base-url (setf *base-url* base-url))
  (when secret (setf *secret* secret))
  (when api-key (setf *api-key* api-key))
  (when space (setf *space* (string-downcase (string space))))
  (values))

(defun setting (var env-name what)
  (or var (uiop:getenv env-name)
      (error "koya client: ~a is not configured (set koya:~(~a~) or ~a)" what var env-name)))

(defun base-url () (string-right-trim "/" (setting *base-url* "KOYA_URL" "the server URL")))
(defun secret () (setting *secret* "KOYA_SECRET" "the owner secret"))
(defun api-key () (setting *api-key* "KOYA_API_KEY" "an API key"))
(defun space-name (space) (string-downcase (string (or space (setting *space* "KOYA_SPACE" "the space")))))

(define-condition koya-error (error)
  ((status :initarg :status :reader koya-error-status)
   (code :initarg :code :reader koya-error-code)
   (message :initarg :message :reader koya-error-message)
   (details :initarg :details :initform nil :reader koya-error-details))
  (:report (lambda (c s) (format s "koya: ~a ~a: ~a" (koya-error-status c) (koya-error-code c) (koya-error-message c)))))

(defun query-alist (query)
  "Kebab plist -> camelCase alist of strings for the query string."
  (loop :for (k v) :on query :by #'cddr
        :when v :collect (cons (camel-key k)
                               (cond ((stringp v) v)
                                     ((listp v) (format nil "~{~a~^,~}" v))
                                     (t (princ-to-string v))))))

(defun build-url (path query)
  (let ((uri (quri:uri (format nil "~a~a" (base-url) path))))
    (when query (setf (quri:uri-query-params uri) (query-alist query)))
    (render-uri uri)))

(defun request (method path &key query body form auth)
  "Perform a request. AUTH is :owner or :api-key. BODY is sent as JSON; FORM, an
alist whose values may be pathnames, as multipart/form-data. Returns the parsed JSON value."
  (let ((headers (list (cons "Accept" "application/json"))))
    (ecase auth
      (:owner (push (cons "Authorization" (format nil "Bearer ~a" (secret))) headers))
      (:api-key (push (cons "X-KOYA-API-KEY" (api-key)) headers))
      ((nil)))
    (when body (push (cons "Content-Type" "application/json") headers))
    (handler-case
        (multiple-value-bind (response-body status)
            (dexador:request (build-url path query) :method method :headers headers
                             :content (cond (body (to-json body)) (form form) (t nil)) :force-string t)
          (declare (ignore status))
          (if (and (stringp response-body) (plusp (length response-body)))
              (parse-json response-body)
              (jobject)))
      (dexador:http-request-failed (e)
        (let* ((text (dexador:response-body e))
               (json (and (stringp text) (ignore-errors (parse-json text))))
               (err (and (hash-table-p json) (jget json "error"))))
          (error 'koya-error
                 :status (dexador:response-status e)
                 :code (or (and err (jget err "code")) "http_error")
                 :message (or (and err (jget err "message")) (format nil "HTTP ~a" (dexador:response-status e)))
                 :details (and err (jvalue->lisp (jget err "details")))))))))

;;; --- Schema -----------------------------------------------------------------

(defun print-changes (changes stream)
  (if (null changes)
      (format stream "~&No changes.~%")
      (dolist (change changes)
        (format stream "~&~:[ ~;!~] ~a~%" (getf change :destructive) (getf change :description)))))

(defun plan (&key (schema (current-schema)) (stream *standard-output*))
  "Show what DEPLOY would change on the server. Returns the list of changes."
  (let* ((response (request :post "/admin/api/schema/plan" :body (schema->jobject schema) :auth :owner))
         (changes (jvalue->lisp (jget response "changes"))))
    (print-changes changes stream)
    changes))

(defun deploy (&key (schema (current-schema)) force (stream *standard-output*) (confirm t))
  "Deploy SCHEMA to the server. Destructive changes are applied only with FORCE, or
after interactive confirmation when CONFIRM is true. Returns the applied changes."
  (flet ((send (force)
           (request :put "/admin/api/schema" :query (and force '(:force "true"))
                                             :body (schema->jobject schema) :auth :owner)))
    (let ((response
            (handler-case (send force)
              (koya-error (e)
                (if (and (= (koya-error-status e) 409) (string= (koya-error-code e) "destructive_changes"))
                    (progn
                      (format stream "~&The deploy contains destructive changes:~%")
                      (print-changes (koya-error-details e) stream)
                      (if (and confirm (y-or-n-p "Apply them anyway?"))
                          (send t)
                          (return-from deploy nil)))
                    (error e))))))
      (let ((applied (jvalue->lisp (jget response "applied"))))
        (format stream "~&Applied ~a change~:p.~%" (length applied))
        applied))))

(defun pull ()
  "Fetch the schema currently stored on the server as a schema object."
  (jobject->schema (request :get "/admin/api/schema" :auth :owner)))

;;; --- Delivery API ------------------------------------------------------------

(defun delivery-path (space model &optional id)
  (format nil "/api/v1/~a/~(~a~)~@[/~a~]" (space-name space) model id))

(defun get-list (model &key space query)
  "List published contents of MODEL. QUERY is a kebab plist (:limit :offset :orders
:fields :filters :include). References are ids unless :include names them, e.g.
:include \"tags\" or :include '(\"tags\" \"author.avatar\")."
  (jvalue->lisp (request :get (delivery-path space model) :query query :auth :api-key)))

(defun get-item (model id &key space query)
  "Fetch one published content. Pass :draft-key in QUERY to preview a draft."
  (jvalue->lisp (request :get (delivery-path space model id) :query query :auth :api-key)))

(defun get-object (model &key space query)
  "Fetch the content of an object-kind model."
  (jvalue->lisp (request :get (delivery-path space model) :query query :auth :api-key)))

;;; --- Admin API: contents ----------------------------------------------------

(defun admin-path (space model &optional id action)
  (format nil "/admin/api/contents/~a/~(~a~)~@[/~a~]~@[/~a~]" (space-name space) model id action))

(defun list-contents (model &key space query)
  "List all contents of MODEL including drafts (owner)."
  (jvalue->lisp (request :get (admin-path space model) :query query :auth :owner)))

(defun get-content (model id &key space)
  (jvalue->lisp (request :get (admin-path space model id) :auth :owner)))

(defun create-content (model data &key space publish id created-at updated-at published-at revised-at)
  "Create a content. DATA is a kebab plist of field values. ID and the system
timestamps CREATED-AT, UPDATED-AT, PUBLISHED-AT and REVISED-AT (ISO 8601 strings)
can be given explicitly, e.g. when importing from another CMS."
  (let ((body (jobject "data" (lisp->jvalue data) "publish" (and publish t))))
    (when id (setf (gethash "id" body) id))
    (loop :for (key value) :on (list "createdAt" created-at "updatedAt" updated-at
                                     "publishedAt" published-at "revisedAt" revised-at)
          :by #'cddr
          :when value :do (setf (gethash key body) value))
    (jvalue->lisp (request :post (admin-path space model) :body body :auth :owner))))

(defun update-content (model id data &key space)
  "Save DATA (kebab plist) as a draft, merged onto the current data."
  (jvalue->lisp (request :patch (admin-path space model id) :body (jobject "data" (lisp->jvalue data)) :auth :owner)))

(defun publish-content (model id &key space data published-at)
  "Publish the draft of content ID, or DATA when given. PUBLISHED-AT overrides the publish date."
  (let ((body (jobject)))
    (when data (setf (gethash "data" body) (lisp->jvalue data)))
    (when published-at (setf (gethash "publishedAt" body) published-at))
    (jvalue->lisp (request :post (admin-path space model id "publish") :body body :auth :owner))))

(defun unpublish-content (model id &key space)
  (jvalue->lisp (request :post (admin-path space model id "unpublish") :body (jobject) :auth :owner)))

(defun delete-content (model id &key space)
  (jvalue->lisp (request :delete (admin-path space model id) :auth :owner)))

(defun draft-key (model id &key space)
  "The draft key of content ID for previews."
  (jget (request :post (admin-path space model id "draft-key") :body (jobject) :auth :owner) "draftKey"))

;;; --- Admin API: API keys ----------------------------------------------------

(defun create-api-key (&key space (label ""))
  "Create a delivery API key for SPACE. Returns (values key id); the key is shown only once."
  (let ((response (request :post (format nil "/admin/api/keys/~a" (space-name space))
                           :body (jobject "label" label) :auth :owner)))
    (values (jget response "key") (jget response "id"))))

(defun list-api-keys (&key space)
  (jvalue->lisp (jget (request :get (format nil "/admin/api/keys/~a" (space-name space)) :auth :owner) "keys")))

(defun webhook-secret (&key space)
  "The secret the server sends as X-KOYA-WEBHOOK-KEY for SPACE's webhooks."
  (jget (request :get (format nil "/admin/api/keys/~a" (space-name space)) :auth :owner) "webhookSecret"))

(defun delete-api-key (id &key space)
  (jvalue->lisp (request :delete (format nil "/admin/api/keys/~a/~a" (space-name space) id) :auth :owner)))

;;; --- Admin API: media -------------------------------------------------------

(defun media-path (space &optional id)
  (format nil "/admin/api/media/~a~@[/~a~]" (space-name space) id))

(defun list-media (&key space search (limit 60) (offset 0))
  "Media of SPACE, newest first: (:media (...) :total-count n :offset :limit). SEARCH matches file names."
  (jvalue->lisp (request :get (media-path space) :query (list :q search :limit limit :offset offset) :auth :owner)))

(defun get-media (id &key space)
  "One media as a plist, including :references (contents that mention it)."
  (jvalue->lisp (request :get (media-path space id) :auth :owner)))

(defun upload-media (file &key space (alt ""))
  "Upload FILE (a pathname or namestring of a PNG, JPEG, GIF or WebP image) to SPACE's
library. Returns the new media as a plist, :url included."
  (first (getf (jvalue->lisp (request :post (media-path space)
                                      :form (list (cons "alt" alt) (cons "file" (pathname file)))
                                      :auth :owner))
               :media)))

(defun update-media (id &key space alt)
  "Change the alt text of media ID."
  (jvalue->lisp (request :patch (media-path space id) :body (jobject "alt" (or alt "")) :auth :owner)))

(defun delete-media (id &key space)
  "Delete media ID and its file."
  (jvalue->lisp (request :delete (media-path space id) :auth :owner)))
