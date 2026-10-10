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
  (:import-from #:koya-core/json #:parse-json)
  (:export #:*db*
           #:*on-rollback*
           #:connect-db
           #:disconnect-db
           #:with-db
           #:with-db-transaction
           #:exec
           #:fetch
           #:fetch-one
           #:col
           #:parsed-col))
(in-package #:koya-server/infra/db/connection)

(defvar *db* nil)
(defvar *db-lock* (make-recursive-lock :name "koya-db"))

(defun connect-db (path)
  (when *db* (disconnect-db))
  (unless (string= path ":memory:")
    (ensure-directories-exist path))
  (setf *db* (connect :sqlite3 :database-name path))
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

(defun parsed-col (row name)
  (let ((v (col row name))) (and v (parse-json v))))
