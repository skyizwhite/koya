(defpackage #:koya-server/infra/db/connection
  (:use #:cl)
  (:import-from #:dbi
                #:connect
                #:disconnect
                #:prepare
                #:execute
                #:fetch-all
                #:do-sql
                #:with-transaction)
  (:import-from #:bordeaux-threads-2
                #:make-recursive-lock
                #:with-recursive-lock-held)
  (:import-from #:koya-server/usecases/ports/store
                #:call-with-transaction #:store-reachable-p)
  (:import-from #:koya-server/domain/html #:html-text)
  (:export #:*db*
           #:*on-rollback*
           #:connect-db
           #:disconnect-db
           #:with-db
           #:with-db-transaction
           #:exec
           #:fetch
           #:fetch-one
           #:col))
(in-package #:koya-server/infra/db/connection)

(defvar *db* nil)
(defvar *db-lock* (make-recursive-lock :name "koya-db"))

(cffi:defcfun ("sqlite3_create_function_v2" %create-function) :int
  (db :pointer) (name :string) (argc :int) (flags :int) (app :pointer)
  (func :pointer) (step :pointer) (final :pointer) (destroy :pointer))
(cffi:defcfun ("sqlite3_value_type" %value-type) :int (value :pointer))
(cffi:defcfun ("sqlite3_value_text" %value-text) :pointer (value :pointer))
(cffi:defcfun ("sqlite3_result_text" %result-text) :void
  (context :pointer) (text :pointer) (length :int) (destroy :pointer))
(cffi:defcfun ("sqlite3_result_null" %result-null) :void (context :pointer))

(defconstant +sqlite-text+ 3)
(defconstant +sqlite-utf8-deterministic+ #x801)

(cffi:defcallback koya-text :void ((context :pointer) (argc :int) (argv :pointer))
  (declare (ignore argc))
  (let ((value (cffi:mem-aref argv :pointer 0)))
    (handler-case
        (if (= (%value-type value) +sqlite-text+)
            (cffi:with-foreign-string ((text size)
                                       (html-text (cffi:foreign-string-to-lisp (%value-text value) :encoding :utf-8))
                                       :encoding :utf-8)
              (%result-text context text (1- size) (cffi:make-pointer (ldb (byte 64 0) -1))))
            (%result-null context))
      (error () (%result-null context)))))

(defun register-functions (connection)
  (%create-function (sqlite::handle (dbi:connection-handle connection)) "koya_text" 1 +sqlite-utf8-deterministic+
                    (cffi:null-pointer) (cffi:callback koya-text)
                    (cffi:null-pointer) (cffi:null-pointer) (cffi:null-pointer)))

(defun connect-db (path)
  (when *db* (disconnect-db))
  (unless (string= path ":memory:")
    (ensure-directories-exist path))
  (setf *db* (connect :sqlite3 :database-name path))
  (register-functions *db*)
  (do-sql *db* "PRAGMA journal_mode = WAL")
  (do-sql *db* "PRAGMA foreign_keys = ON")
  (do-sql *db* "PRAGMA busy_timeout = 5000")
  *db*)

(defun disconnect-db ()
  (when *db*
    (disconnect *db*)
    (setf *db* nil)))

(defmacro with-db (&body body)
  `(with-recursive-lock-held (*db-lock*)
     (unless *db* (error "Database is not connected"))
     ,@body))

(defvar *on-rollback* '())

(defmacro with-db-transaction (&body body)
  `(with-db
     (let ((done nil))
       (unwind-protect
            (multiple-value-prog1 (with-transaction *db* ,@body)
              (setf done t))
         (unless done (mapc #'funcall *on-rollback*))))))

(defmethod call-with-transaction (thunk)
  (with-db-transaction (funcall thunk)))

(defmethod store-reachable-p ()
  (handler-case (and (fetch-one "SELECT count(*) AS n FROM spaces") t)
    (error () nil)))

(defun exec (sql &rest params)
  (with-db (do-sql *db* sql params)))

(defun fetch (sql &rest params)
  (with-db (fetch-all (execute (prepare *db* sql) params))))

(defun fetch-one (sql &rest params)
  (first (apply #'fetch sql params)))

(defun col (row name)
  (getf row (intern name :keyword)))
