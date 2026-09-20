(defpackage #:koya-server/lib/http
  (:use #:cl)
  (:import-from #:jingle
                #:set-response-header #:set-response-status #:get-request-header)
  (:import-from #:ningle
                #:*request* #:*response* #:process-response)
  (:import-from #:lack/request
                #:request-content)
  (:import-from #:lack/response
                #:response-status)
  (:import-from #:koya/core/json
                #:parse-json #:to-json #:jobject)
  (:import-from #:koya/core/schema
                #:schema-error #:schema-error-message)
  (:import-from #:koya/core/validate
                #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/lib/query
                #:query-error #:query-error-message)
  (:import-from #:koya-server/lib/env
                #:dev-mode-p #:base-url)
  (:import-from #:quri
                #:uri #:uri-scheme #:uri-host #:uri-port)
  (:import-from #:babel
                #:octets-to-string)
  (:import-from #:alexandria
                #:read-stream-content-into-byte-vector)
  (:export #:json-app
           #:make-json-app
           #:api-error
           #:api-error-status
           #:fail-api
           #:read-json-body
           #:path-param
           #:query-param
           #:body-field
           #:form-field
           #:uploaded-files
           #:header
           #:origin-allowed-p
           #:error-object
           #:json-response
           #:ok-status))
(in-package #:koya-server/lib/http)

;;; Shared plumbing for the two JSON apps (delivery and admin API).

(define-condition api-error (error)
  ((status :initarg :status :reader api-error-status)
   (code :initarg :code :reader api-error-code)
   (message :initarg :message :reader api-error-message)
   (details :initarg :details :initform nil :reader api-error-details))
  (:report (lambda (c s) (format s "~a ~a: ~a" (api-error-status c) (api-error-code c) (api-error-message c)))))

(defun fail-api (status code message &optional details)
  (error 'api-error :status status :code code :message message :details details))

(defun error-object (code message &optional details)
  (let ((err (jobject "code" code "message" message)))
    (when details (setf (gethash "details" err) details))
    (jobject "error" err)))

(defun json-response (status object)
  (list status
        (list :content-type "application/json; charset=utf-8")
        (list (to-json object))))

(defun validation-details (errors)
  (map 'vector (lambda (e) (jobject "field" (getf e :field) "code" (getf e :code) "message" (getf e :message)))
       errors))

(defclass json-app (jingle:app) ()
  (:documentation "A jingle app whose handlers return JSON values (hash tables,
vectors, strings...) and whose errors become JSON error responses."))

(defun make-json-app ()
  (make-instance 'json-app))

(defmethod lack/component:call :around ((app json-app) env)
  (handler-case (call-next-method)
    (api-error (e)
      (json-response (api-error-status e)
                     (error-object (api-error-code e) (api-error-message e) (api-error-details e))))
    (query-error (e)
      (json-response 400 (error-object "bad_query" (query-error-message e))))
    (schema-error (e)
      (json-response 400 (error-object "invalid_schema" (schema-error-message e))))
    (validation-error (e)
      (json-response 422 (error-object "validation_failed" "Content is invalid"
                                       (validation-details (validation-error-errors e)))))
    (error (e)
      (format *error-output* "~&[koya] unhandled error: ~a~%" e)
      (json-response 500 (error-object "internal_error"
                                       (if (dev-mode-p) (princ-to-string e) "Internal server error"))))))

(defmethod process-response :around ((app json-app) result)
  (set-response-header :content-type "application/json; charset=utf-8")
  (call-next-method app (if (stringp result) result (to-json result))))

(defun ok-status (status)
  (set-response-status status))

(defun read-json-body ()
  "Parse the request body as JSON. Signals a 400 API error when it is not a JSON object."
  (let* ((octets (request-content *request*))
         (text (octets-to-string octets :encoding :utf-8))
         (value (if (zerop (length (string-trim '(#\Space #\Newline #\Return #\Tab) text)))
                    (jobject)
                    (handler-case (parse-json text)
                      (error () (fail-api 400 "bad_json" "Request body is not valid JSON"))))))
    (unless (hash-table-p value)
      (fail-api 400 "bad_json" "Request body must be a JSON object"))
    value))

(defun path-param (params key)
  (cdr (assoc key params)))

(defun query-param (params name)
  (let ((v (cdr (assoc name params :test #'equal))))
    (if (and (stringp v) (string= v "")) nil v)))

(defun body-field (body name &optional default)
  (multiple-value-bind (v found) (gethash name body)
    (if found v default)))

(defun form-field (params name)
  "A plain (non-file) form field, or NIL when absent or blank."
  (let ((v (cdr (assoc name params :test #'equal))))
    (and (stringp v) (plusp (length (string-trim " " v))) (string-trim " " v))))

(defun uploaded-files (params name)
  "Files posted under NAME as a list of (octets filename content-type). A multipart
file part arrives from lack as (stream filename content-type); one name may repeat."
  (loop :for (k . v) :in params
        :when (and (equal k name) (consp v) (streamp (first v)))
          :collect (destructuring-bind (stream &optional filename content-type) v
                     (list (read-stream-content-into-byte-vector stream) filename content-type))))

(defun header (name)
  (let ((values (get-request-header name)))
    (and values (string-trim " " (first values)))))

;;; --- Same-origin check (CSRF) --------------------------------------------------

(defun origin-key (url)
  "host or host:port of URL, lowercased, with the scheme's default port dropped.
NIL when URL has no host, which includes the literal \"null\" browsers send from
sandboxed or opaque origins."
  (let ((u (ignore-errors (uri (string-trim " " url)))))
    (and u (uri-host u)
         (let* ((scheme (string-downcase (or (uri-scheme u) "")))
                (port (uri-port u))
                (default (cond ((string= scheme "https") 443) ((string= scheme "http") 80))))
           (string-downcase
            (if (or (null port) (eql port default))
                (uri-host u)
                (format nil "~a:~a" (uri-host u) port)))))))

(defun host-key (host)
  "The Host header in the same shape as ORIGIN-KEY: default ports are dropped."
  (let ((host (string-downcase (string-trim " " (or host "")))))
    (dolist (suffix '(":80" ":443") host)
      (let ((n (- (length host) (length suffix))))
        (when (and (plusp n) (string= host suffix :start1 n))
          (return (subseq host 0 n)))))))

(defun origin-allowed-p (origin referer host &optional (base (base-url)))
  "CSRF check for state-changing requests. The Origin header (or Referer when
Origin is absent) must name the Host or KOYA_BASE_URL. A request with neither
header is accepted: non-browser clients. A present but unusable Origin such as
\"null\" is rejected."
  (let ((source (or origin referer)))
    (or (null source)
        (let ((key (origin-key source)))
          (and key
               (or (string= key (host-key host))
                   (let ((base-key (origin-key base))) (and base-key (string= key base-key)))))))))
