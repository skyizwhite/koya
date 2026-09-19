(defpackage #:koya-server/db/connection
  (:use #:cl)
  (:import-from #:dbi
                #:connect
                #:disconnect
                #:prepare
                #:execute
                #:fetch-all
                #:do-sql
                #:with-transaction)
  (:import-from #:sxql
                #:yield)
  (:import-from #:bordeaux-threads-2
                #:make-recursive-lock
                #:with-recursive-lock-held)
  (:export #:*db*
           #:connect-db
           #:disconnect-db
           #:with-db
           #:with-db-transaction
           #:exec
           #:fetch
           #:fetch-one
           #:run
           #:query
           #:query-one
           #:col))
(in-package #:koya-server/db/connection)

;;; A single SQLite connection guarded by a recursive lock. SQLite serializes
;;; writers anyway, and one connection keeps transactions simple.

(defvar *db* nil)
(defvar *db-lock* (make-recursive-lock :name "koya-db"))

(defun connect-db (path)
  "Open (or reuse) the database at PATH. \":memory:\" gives a private in-memory database."
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

(defmacro with-db-transaction (&body body)
  `(with-db (with-transaction *db* ,@body)))

(defun exec (sql &rest params)
  "Run a statement that returns no rows."
  (with-db (do-sql *db* sql params)))

(defun fetch (sql &rest params)
  "Run a query and return all rows as plists with :|column| keys."
  (with-db (fetch-all (execute (prepare *db* sql) params))))

(defun fetch-one (sql &rest params)
  (first (apply #'fetch sql params)))

(defun run (statement)
  "Execute an SxQL statement that returns no rows."
  (multiple-value-bind (sql params) (yield statement)
    (apply #'exec sql params)))

(defun query (statement)
  "Execute an SxQL statement and return rows."
  (multiple-value-bind (sql params) (yield statement)
    (apply #'fetch sql params)))

(defun query-one (statement)
  (first (query statement)))

(defun col (row name)
  "Column NAME (a string) of ROW."
  (getf row (intern name :keyword)))
