(defpackage #:koya-server/infra/db/schema-dump
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:*db* #:connect-db #:disconnect-db #:fetch #:col)
  (:import-from #:koya-server/infra/db/migrations #:migrate #:current-version)
  (:export #:snapshot
           #:migrated-snapshot
           #:snapshot-path
           #:read-snapshot
           #:write-snapshot))
(in-package #:koya-server/infra/db/schema-dump)

;;; The migrations are the schema's only definition; this reads the shape they
;;; add up to back out of SQLite and writes it to schema.sql beside this file, so
;;; the current schema can be read in one place without replaying six versions
;;; of DDL in your head. The file is generated, never edited: a test in
;;; tests/server/infra/db.lisp fails if it drifts from the migrations.

(defun snapshot-path ()
  (asdf:system-relative-pathname "koya-server" "src/server/infra/db/schema.sql"))

(defun reindent (sql)
  "Re-indent a stored CREATE statement so every continuation line sits one level
in, whatever indentation the migration's Lisp source happened to give it."
  (let ((lines (uiop:split-string (string-trim '(#\Space #\Tab #\Newline) sql)
                                  :separator '(#\Newline))))
    (format nil "~a~{~%  ~a~}"
            (string-right-trim '(#\Space #\Tab) (first lines))
            (mapcar (lambda (line) (string-trim '(#\Space #\Tab) line)) (rest lines)))))

(defun ddl-statements ()
  "Every CREATE statement of the connected database, each table followed by its
own indexes. Names order the rows, so the dump does not move when a later
migration happens to create a table earlier."
  (mapcar (lambda (row) (reindent (col row "sql")))
          (fetch "SELECT sql FROM sqlite_master
                  WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'
                  ORDER BY tbl_name, CASE type WHEN 'table' THEN 0 ELSE 1 END, name")))

(defun snapshot ()
  "The connected database's schema as a SQL script."
  (format nil "~
-- koya database schema, version ~a.
--
-- Generated from src/server/infra/db/migrations.lisp; do not edit by hand.
-- Regenerate it from the REPL with (koya-server:write-schema-snapshot).
~{~%~a;~}~%"
          (current-version) (ddl-statements)))

(defun migrated-snapshot ()
  "SNAPSHOT of a throwaway in-memory database with every migration applied.
*DB* is rebound, so this leaves a connected database (a running server's, or a
test's) alone."
  (let ((*db* nil))
    (connect-db ":memory:")
    (unwind-protect (progn (migrate) (snapshot))
      (disconnect-db))))

(defun read-snapshot (&optional (path (snapshot-path)))
  (when (probe-file path)
    (uiop:read-file-string path)))

(defun write-snapshot (&optional (path (snapshot-path)))
  "Regenerate src/server/infra/db/schema.sql. Run it after adding a migration."
  (let ((text (migrated-snapshot)))
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create :external-format :utf-8)
      (write-string text out))
    (format t "~&[koya] wrote ~a~%" path)
    path))
