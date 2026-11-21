(defpackage #:koya-server/infra/db/connection
  (:use #:cl)
  (:import-from #:dbi
                #:connect
                #:disconnect
                #:prepare
                #:execute
                #:fetch-all
                #:free-query-resources)
  (:import-from #:bordeaux-threads-2
                #:make-recursive-lock
                #:with-recursive-lock-held)
  (:import-from #:koya-server/usecases/ports/store
                #:call-with-transaction #:store-reachable-p)
  (:export #:*db*
           #:*on-rollback*
           #:connect-db
           #:disconnect-db
           #:with-db
           #:with-db-transaction
           #:in-transaction-p
           #:exec
           #:fetch
           #:fetch-one
           #:col))
(in-package #:koya-server/infra/db/connection)

(defvar *db* nil)
(defvar *db-lock* (make-recursive-lock :name "koya-db"))

(defun connect-db (path)
  (when *db* (disconnect-db))
  (unless (string= path ":memory:")
    (ensure-directories-exist path))
  (setf *db* (connect :sqlite3 :database-name path))
  (exec "PRAGMA journal_mode = WAL")
  (exec "PRAGMA foreign_keys = ON")
  (exec "PRAGMA busy_timeout = 5000")
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

(defvar *transactions* 0)

(defun in-transaction-p ()
  (plusp *transactions*))

(defun call-in-db-transaction (thunk)
  (with-db
    (let ((done nil))
      (exec "SAVEPOINT koya")
      (incf *transactions*)
      (unwind-protect
           (multiple-value-prog1 (funcall thunk)
             (exec "RELEASE koya")
             (setf done t))
        (decf *transactions*)
        (unless done
          (mapc #'funcall *on-rollback*)
          (exec "ROLLBACK TO koya")
          (exec "RELEASE koya"))))))

(defmacro with-db-transaction (&body body)
  `(call-in-db-transaction (lambda () ,@body)))

(defmethod call-with-transaction (thunk)
  (call-in-db-transaction thunk))

(defmethod store-reachable-p ()
  (handler-case (and (fetch-one "SELECT count(*) AS n FROM spaces") t)
    (error () nil)))

(defun run (sql params)
  (with-db
    (let ((query (prepare *db* sql)))
      (unwind-protect (fetch-all (execute query params))
        (free-query-resources query)))))

(defun exec (sql &rest params)
  (run sql params)
  nil)

(defun fetch (sql &rest params)
  (run sql params))

(defun fetch-one (sql &rest params)
  (first (apply #'fetch sql params)))

(defun col (row name)
  (getf row (intern name :keyword)))
