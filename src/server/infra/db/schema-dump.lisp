(defpackage #:koya-server/infra/db/schema-dump
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:*db* #:connect-db #:disconnect-db #:fetch #:col)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:export #:snapshot
           #:migrated-snapshot
           #:snapshot-path
           #:read-snapshot
           #:write-snapshot))
(in-package #:koya-server/infra/db/schema-dump)

(defun snapshot-path ()
  (asdf:system-relative-pathname "koya-server" "src/server/infra/db/schema.sql"))

(defun reindent (sql)
  (let ((lines (uiop:split-string (string-trim '(#\Space #\Tab #\Newline) sql)
                                  :separator '(#\Newline))))
    (format nil "~a~{~%  ~a~}"
            (string-right-trim '(#\Space #\Tab) (first lines))
            (mapcar (lambda (line) (string-trim '(#\Space #\Tab) line)) (rest lines)))))

(defun ddl-statements ()
  (mapcar (lambda (row) (reindent (col row "sql")))
          (fetch "SELECT sql FROM sqlite_master
                  WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'
                  ORDER BY tbl_name, CASE type WHEN 'table' THEN 0 ELSE 1 END, name")))

(defun snapshot ()
  (format nil "~{~a;~%~}" (ddl-statements)))

(defun migrated-snapshot ()
  (let ((*db* nil))
    (connect-db ":memory:")
    (unwind-protect (progn (migrate) (snapshot))
      (disconnect-db))))

(defun read-snapshot (&optional (path (snapshot-path)))
  (when (probe-file path)
    (uiop:read-file-string path)))

(defun write-snapshot (&optional (path (snapshot-path)))
  (let ((text (migrated-snapshot)))
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create :external-format :utf-8)
      (write-string text out))
    (format t "~&[koya] wrote ~a~%" path)
    path))
