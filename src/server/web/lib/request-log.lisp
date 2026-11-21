(defpackage #:koya-server/web/lib/request-log
  (:use #:cl)
  (:import-from #:lack-mw #:with-args #:*mw-accesslog* #:default-formatter)
  (:import-from #:alexandria #:copy-hash-table)
  (:import-from #:koya-server/log #:log-error)
  (:export #:log-unhandled
           #:*mw-error-log*
           #:*mw-access-log*))
(in-package #:koya-server/web/lib/request-log)

(defparameter +frames-logged+ 40)

(defun frame-names ()
  (let ((names '())
        (*package* (find-package :keyword)))
    (sb-debug:map-backtrace
     (lambda (frame)
       (push (prin1-to-string (sb-di:debug-fun-name (sb-di:frame-debug-fun frame))) names))
     :count +frames-logged+)
    (nreverse names)))

(defun condition-text (condition)
  (handler-case (let ((*print-length* 50) (*print-level* 5) (*print-circle* t))
                  (princ-to-string condition))
    (error () (format nil "a ~a that cannot be printed" (type-of condition)))))

(defun without-query (url)
  (and url (subseq url 0 (position #\? url))))

(defun request-path (env)
  (without-query (or (getf env :request-uri) "")))

(defun log-unhandled (condition env)
  (log-error :koya.http "~a ~a: ~a~%~{  ~a~%~}"
             (getf env :request-method) (request-path env) (condition-text condition) (frame-names)))

(defparameter *mw-error-log*
  (lambda (app)
    (lambda (env)
      (handler-bind ((error (lambda (condition) (log-unhandled condition env))))
        (funcall app env)))))

(defun without-queries (env)
  (let ((env (copy-list env))
        (headers (copy-hash-table (getf env :headers))))
    (setf (getf env :request-uri) (request-path env))
    (when (gethash "referer" headers)
      (setf (gethash "referer" headers) (without-query (gethash "referer" headers))))
    (setf (getf env :headers) headers)
    env))

(defparameter *mw-access-log*
  (with-args *mw-accesslog*
    :formatter (lambda (env response now) (default-formatter (without-queries env) response now))))
