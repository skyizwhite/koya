(defpackage #:koya-sdk/client
  (:use #:cl)
  (:import-from #:koya-core/json
                #:parse-json #:to-json #:jobject #:jget #:json-null)
  (:import-from #:koya-core/case
                #:camel-key #:jvalue->lisp #:lisp->jvalue)
  (:import-from #:koya-core/schema
                #:schema->jobject #:jobject->schema)
  (:import-from #:koya-core/diff
                #:format-change)
  (:import-from #:koya-sdk/config
                #:current-schema)
  (:import-from #:dexador)
  (:import-from #:quri
                #:make-uri #:render-uri)
  (:export #:*base-url* #:*management-key* #:*delivery-key* #:*space*
           #:configure
           #:koya-error #:koya-error-status #:koya-error-code #:koya-error-message #:koya-error-details
           #:plan #:deploy #:pull
           #:get-list #:get-item #:get-object
           #:list-contents #:get-content #:create-content #:update-content
           #:publish-content #:unpublish-content #:discard-draft #:delete-content #:draft-key
           #:get-object-content #:update-object #:publish-object #:unpublish-object
           #:discard-object-draft #:object-draft-key
           #:create-delivery-key #:list-delivery-keys #:delete-delivery-key #:webhook-secret
           #:list-media #:get-media #:upload-media #:update-media #:delete-media))
(in-package #:koya-sdk/client)

(defvar *base-url* nil "Server URL, e.g. https://cms.example.com. Falls back to KOYA_URL.")
(defvar *management-key* nil "Management key for admin calls. Falls back to KOYA_MANAGEMENT_KEY.")
(defvar *delivery-key* nil "Delivery key. Falls back to KOYA_DELIVERY_KEY.")
(defvar *space* nil "Default space for content calls. Falls back to KOYA_SPACE.")

(defun configure (&key base-url management-key delivery-key space)
  "Set *BASE-URL*, *MANAGEMENT-KEY*, *DELIVERY-KEY* and *SPACE* from the arguments
given; the others keep their values."
  (when base-url (setf *base-url* base-url))
  (when management-key (setf *management-key* management-key))
  (when delivery-key (setf *delivery-key* delivery-key))
  (when space (setf *space* (string-downcase (string space))))
  (values))

(defun setting (var env-name what)
  (or (symbol-value var) (uiop:getenv env-name)
      (error "koya client: ~a is not configured (set koya-sdk:~(~a~) or ~a)" what var env-name)))

(defun base-url () (string-right-trim "/" (setting '*base-url* "KOYA_URL" "the server URL")))
(defun management-key () (setting '*management-key* "KOYA_MANAGEMENT_KEY" "a management key"))
(defun delivery-key () (setting '*delivery-key* "KOYA_DELIVERY_KEY" "a delivery key"))
(defun space-name (space) (string-downcase (string (or space (setting '*space* "KOYA_SPACE" "the space")))))

(define-condition koya-error (error)
  ((status :initarg :status :reader koya-error-status)
   (code :initarg :code :reader koya-error-code)
   (message :initarg :message :reader koya-error-message)
   (details :initarg :details :initform nil :reader koya-error-details))
  (:documentation "Signalled for any answer but a 2xx. KOYA-ERROR-STATUS is the HTTP status,
KOYA-ERROR-CODE and KOYA-ERROR-MESSAGE the error object's code and message, and
KOYA-ERROR-DETAILS its details: the problems of a 422, or the changes a refused
deploy would make.")
  (:report (lambda (c s) (format s "koya: ~a ~a: ~a" (koya-error-status c) (koya-error-code c) (koya-error-message c)))))

(defun query-alist (query)
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
  (let ((headers (list (cons "Accept" "application/json"))))
    (ecase auth
      (:management (push (cons "Authorization" (format nil "Bearer ~a" (management-key))) headers))
      (:delivery (push (cons "X-KOYA-DELIVERY-KEY" (delivery-key)) headers))
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

(defun print-changes (changes stream)
  (if (null changes)
      (format stream "~&No changes.~%")
      (dolist (change changes)
        (format stream "~&~:[ ~;!~] ~a~%" (getf change :destructive) (getf change :description))
        (dolist (misfit (getf change :misfits))
          (format stream "~&    ~a ~a (~a): ~a~%" (getf misfit :id) (getf misfit :field)
                  (getf misfit :version) (getf misfit :message))))))

(defun schema-path (space &optional action)
  (format nil "/admin/api/schema/~a~@[/~a~]" (space-name space) action))

(defun plan (&key space (schema (current-schema)) (stream *standard-output*))
  "Show what DEPLOY would change in SPACE. Returns the list of changes."
  (let* ((response (request :post (schema-path space "plan") :body (schema->jobject schema) :auth :management))
         (changes (jvalue->lisp (jget response "changes"))))
    (print-changes changes stream)
    changes))

(defun deploy (&key space (schema (current-schema)) force (stream *standard-output*) (confirm t))
  "Deploy SCHEMA to SPACE, which must already exist -- spaces are made in the admin
UI. Destructive changes are applied only with FORCE, or after interactive
confirmation when CONFIRM is true. Returns the applied changes."
  (flet ((send (force)
           (request :put (schema-path space) :query (and force '(:force "true"))
                                             :body (schema->jobject schema) :auth :management)))
    (let ((response
            (handler-case (send force)
              (koya-error (e)
                (cond ((and (= (koya-error-status e) 409) (string= (koya-error-code e) "destructive_changes"))
                       (format stream "~&The deploy contains destructive changes:~%")
                       (print-changes (koya-error-details e) stream)
                       (if (and confirm (y-or-n-p "Apply them anyway?"))
                           (send t)
                           (return-from deploy nil)))
                      ((and (= (koya-error-status e) 409) (string= (koya-error-code e) "contents_do_not_fit"))
                       (format stream "~&The deploy is refused: these contents do not fit it yet:~%")
                       (print-changes (koya-error-details e) stream)
                       (error e))
                      (t (error e)))))))
      (let ((applied (jvalue->lisp (jget response "applied"))))
        (format stream "~&Applied ~a change~:p.~%" (length applied))
        applied))))

(defun pull (&key space)
  "Fetch the schema SPACE currently has on the server as a schema object."
  (jobject->schema (request :get (schema-path space) :auth :management)))

(defun delivery-path (space model &optional id)
  (format nil "/api/v1/~a/~(~a~)~@[/~a~]" (space-name space) model id))

(defun get-list (model &key space query)
  "List published contents of MODEL. QUERY is a kebab plist (:limit :offset :orders
:fields :filters :include). References are ids unless :include names them, e.g.
:include \"tags\" or :include '(\"tags\" \"author.avatar\")."
  (jvalue->lisp (request :get (delivery-path space model) :query query :auth :delivery)))

(defun get-item (model id &key space query)
  "Fetch one published content. Pass :draft-key in QUERY to preview a draft."
  (jvalue->lisp (request :get (delivery-path space model id) :query query :auth :delivery)))

(defun get-object (model &key space query)
  "Fetch the content of an object-kind model."
  (jvalue->lisp (request :get (delivery-path space model) :query query :auth :delivery)))

(defun admin-path (space model &optional id action)
  (format nil "/admin/api/contents/~a/~(~a~)~@[/~a~]~@[/~a~]" (space-name space) model id action))

(defun list-contents (model &key space query)
  "List all contents of MODEL including drafts (management)."
  (jvalue->lisp (request :get (admin-path space model) :query query :auth :management)))

(defun get-content (model id &key space)
  "Content ID of MODEL as the admin API has it, draft included."
  (jvalue->lisp (request :get (admin-path space model id) :auth :management)))

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
    (jvalue->lisp (request :post (admin-path space model) :body body :auth :management))))

(defun update-content (model id data &key space)
  "Save DATA (kebab plist) as a draft, merged onto the current data."
  (jvalue->lisp (request :patch (admin-path space model id) :body (jobject "data" (lisp->jvalue data)) :auth :management)))

(defun publish-content (model id &key space data published-at)
  "Publish the draft of content ID, or DATA when given. PUBLISHED-AT overrides the publish date."
  (let ((body (jobject)))
    (when data (setf (gethash "data" body) (lisp->jvalue data)))
    (when published-at (setf (gethash "publishedAt" body) published-at))
    (jvalue->lisp (request :post (admin-path space model id "publish") :body body :auth :management))))

(defun unpublish-content (model id &key space)
  "Take content ID off the delivery API, keeping it as a draft."
  (jvalue->lisp (request :post (admin-path space model id "unpublish") :body (jobject) :auth :management)))

(defun discard-draft (model id &key space)
  "Drop the draft of a published content, leaving the published version."
  (jvalue->lisp (request :post (admin-path space model id "discard-draft") :body (jobject) :auth :management)))

(defun delete-content (model id &key space)
  "Delete content ID with its history. Refused while other contents refer to it."
  (jvalue->lisp (request :delete (admin-path space model id) :auth :management)))

(defun draft-key (model id &key space)
  "The draft key of content ID for previews."
  (jget (request :post (admin-path space model id "draft-key") :body (jobject) :auth :management) "draftKey"))

(defun get-object-content (model &key space)
  "The content of object model MODEL as the admin API has it, draft included."
  (jvalue->lisp (request :get (admin-path space model) :auth :management)))

(defun update-object (model data &key space)
  "Save DATA (kebab plist) as the draft of object model MODEL, merged onto the
current data. The first save makes its content."
  (jvalue->lisp (request :patch (admin-path space model) :body (jobject "data" (lisp->jvalue data)) :auth :management)))

(defun publish-object (model &key space data published-at)
  "Publish the draft of object model MODEL, or DATA when given; DATA makes its
content when it has none yet. PUBLISHED-AT overrides the publish date."
  (let ((body (jobject)))
    (when data (setf (gethash "data" body) (lisp->jvalue data)))
    (when published-at (setf (gethash "publishedAt" body) published-at))
    (jvalue->lisp (request :post (admin-path space model nil "publish") :body body :auth :management))))

(defun unpublish-object (model &key space)
  "Take object model MODEL off the delivery API, keeping its content as a draft."
  (jvalue->lisp (request :post (admin-path space model nil "unpublish") :body (jobject) :auth :management)))

(defun discard-object-draft (model &key space)
  "Drop the draft of object model MODEL, leaving the published version."
  (jvalue->lisp (request :post (admin-path space model nil "discard-draft") :body (jobject) :auth :management)))

(defun object-draft-key (model &key space)
  "The draft key of object model MODEL for previews."
  (jget (request :post (admin-path space model nil "draft-key") :body (jobject) :auth :management) "draftKey"))

(defun create-delivery-key (&key space (label ""))
  "Create a delivery key for SPACE. Returns (values key id); it is shown only once."
  (let ((response (request :post (format nil "/admin/api/keys/~a" (space-name space))
                           :body (jobject "label" label) :auth :management)))
    (values (jget response "key") (jget response "id"))))

(defun list-delivery-keys (&key space)
  "The delivery keys of SPACE, without their plaintext."
  (jvalue->lisp (jget (request :get (format nil "/admin/api/keys/~a" (space-name space)) :auth :management) "keys")))

(defun webhook-secret (&key space)
  "The secret the server sends as X-KOYA-WEBHOOK-KEY for SPACE's webhooks."
  (jget (request :get (format nil "/admin/api/keys/~a" (space-name space)) :auth :management) "webhookSecret"))

(defun delete-delivery-key (id &key space)
  "Revoke the delivery key ID of SPACE."
  (jvalue->lisp (request :delete (format nil "/admin/api/keys/~a/~a" (space-name space) id) :auth :management)))

(defun media-path (space &optional id)
  (format nil "/admin/api/media/~a~@[/~a~]" (space-name space) id))

(defun list-media (&key space search (limit 60) (offset 0))
  "Media of SPACE, newest first: (:media (...) :total-count n :offset :limit). SEARCH matches file names."
  (jvalue->lisp (request :get (media-path space) :query (list :q search :limit limit :offset offset) :auth :management)))

(defun get-media (id &key space)
  "One media as a plist, including :references (contents that mention it)."
  (jvalue->lisp (request :get (media-path space id) :auth :management)))

(defun upload-media (file &key space (alt ""))
  "Upload FILE (a pathname or namestring of a PNG, JPEG, GIF or WebP image) to SPACE's
library. Returns the new media as a plist, :url included."
  (first (getf (jvalue->lisp (request :post (media-path space)
                                      :form (list (cons "alt" alt) (cons "file" (pathname file)))
                                      :auth :management))
               :media)))

(defun update-media (id &key space alt)
  "Change the alt text of media ID."
  (jvalue->lisp (request :patch (media-path space id) :body (jobject "alt" (or alt "")) :auth :management)))

(defun delete-media (id &key space)
  "Delete media ID and its file."
  (jvalue->lisp (request :delete (media-path space id) :auth :management)))
