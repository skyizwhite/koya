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
                #:dev-mode-p)
  (:import-from #:babel
                #:octets-to-string)
  (:export #:json-app
           #:make-json-app
           #:api-error
           #:api-error-status
           #:fail-api
           #:read-json-body
           #:path-param
           #:query-param
           #:body-field
           #:header
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

(defun header (name)
  (let ((values (get-request-header name)))
    (and values (string-trim " " (first values)))))
