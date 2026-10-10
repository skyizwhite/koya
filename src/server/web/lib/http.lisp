(defpackage #:koya-server/web/lib/http
  (:use #:cl)
  (:import-from #:jingle
                #:set-response-header #:set-response-status #:get-request-header #:redirect
                #:*request* #:process-response #:request-content)
  (:import-from #:koya-core/json
                #:parse-json #:to-json #:jobject #:blank-p)
  (:import-from #:koya-core/schema
                #:schema-error #:schema-error-message)
  (:import-from #:koya-core/validate
                #:validation-error #:validation-error-errors)
  (:import-from #:koya-server/domain/errors
                #:koya-error #:koya-error-code #:koya-error-message #:koya-error-details
                #:not-found #:conflict #:invalid-input #:rejected #:too-large)
  (:import-from #:koya-server/usecases/system #:dev-mode-p #:public-url)
  (:import-from #:quri
                #:uri #:uri-scheme #:uri-host #:uri-port #:uri-error)
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
           #:param
           #:integer-param
           #:integer-text
           #:redirect-to
           #:body-field
           #:form-field
           #:form-values
           #:form-list
           #:uploaded-files
           #:header
           #:origin-allowed-p
           #:error-object
           #:json-response
           #:error-status
           #:ok-status))
(in-package #:koya-server/web/lib/http)

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

(defun error-status (condition)
  (etypecase condition
    (not-found 404)
    (conflict 409)
    (invalid-input 400)
    (rejected 422)
    (too-large 413)))

(defun validation-details (errors)
  (map 'vector (lambda (e) (jobject "field" (getf e :field) "code" (getf e :code) "message" (getf e :message)))
       errors))

(defclass json-app (jingle:app) ())

(defun make-json-app ()
  (make-instance 'json-app))

(defmethod lack/component:call :around ((app json-app) env)
  (handler-case (let ((answer (call-next-method)))
                  (if (equal answer '(400 () ("Bad Request")))
                      (json-response 400 (error-object "bad_json" "Request body could not be read"))
                      answer))
    (api-error (e)
      (json-response (api-error-status e)
                     (error-object (api-error-code e) (api-error-message e) (api-error-details e))))
    (koya-error (e)
      (json-response (error-status e)
                     (error-object (koya-error-code e) (koya-error-message e) (koya-error-details e))))
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

(defun param (params name)
  (let ((v (cdr (assoc name params :test #'equal))))
    (and (stringp v) (not (blank-p v)) v)))

(defun integer-text (text)
  (and text (handler-case (parse-integer text) (parse-error () nil))))

(defun integer-param (params name)
  (integer-text (param params name)))

(defun redirect-to (path &optional (status 303))
  (redirect path status))

(defun body-field (body name &optional default)
  (multiple-value-bind (v found) (gethash name body)
    (if found v default)))

(defun form-field (params name)
  (let ((v (cdr (assoc name params :test #'equal))))
    (and (stringp v) (plusp (length (string-trim " " v))) (string-trim " " v))))

(defun form-values (params name)
  (loop :for (k . v) :in params
        :when (and (stringp k) (string= k name)) :collect v))

(defun form-list (params name)
  (loop :for value :in (form-values params name)
        :when (stringp value)
          :append (remove "" (uiop:split-string value :separator ",") :test #'string=)))

(defun uploaded-files (params name)
  (loop :for (k . v) :in params
        :when (and (equal k name) (consp v) (streamp (first v)))
          :collect (destructuring-bind (stream &optional filename content-type) v
                     (list (read-stream-content-into-byte-vector stream) filename content-type))))

(defun header (name)
  (let ((values (get-request-header name)))
    (and values (string-trim " " (first values)))))

(defun origin-key (url)
  (let ((u (handler-case (uri (string-trim " " url)) (uri-error () nil))))
    (and u (uri-host u)
         (let* ((scheme (string-downcase (or (uri-scheme u) "")))
                (port (uri-port u))
                (default (cond ((string= scheme "https") 443) ((string= scheme "http") 80))))
           (string-downcase
            (if (or (null port) (eql port default))
                (uri-host u)
                (format nil "~a:~a" (uri-host u) port)))))))

(defun host-key (host)
  (let ((host (string-downcase (string-trim " " (or host "")))))
    (dolist (suffix '(":80" ":443") host)
      (let ((n (- (length host) (length suffix))))
        (when (and (plusp n) (string= host suffix :start1 n))
          (return (subseq host 0 n)))))))

(defun origin-allowed-p (origin referer host &optional (base (public-url)))
  (let ((source (or origin referer)))
    (or (null source)
        (let ((key (origin-key source)))
          (and key
               (or (string= key (host-key host))
                   (let ((base-key (origin-key base))) (and base-key (string= key base-key)))))))))
