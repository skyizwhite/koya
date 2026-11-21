(defpackage #:koya-server/infra/db/sql
  (:use #:cl)
  (:export #:sql
           #:sql-text
           #:sql-params
           #:bound
           #:fragment
           #:separated
           #:all-of
           #:any-of
           #:in-list
           #:like-pattern
           #:json-path
           #:json-at))
(in-package #:koya-server/infra/db/sql)

(defun sql (text &rest params)
  (cons text params))

(defun sql-text (sql)
  (car sql))

(defun sql-params (sql)
  (cdr sql))

(defun bound (value)
  (sql "?" value))

(defun params-of (parts)
  (loop :for part :in parts :append (sql-params part)))

(defun fragment (control &rest parts)
  (apply #'sql (apply #'format nil control (mapcar #'sql-text parts)) (params-of parts)))

(defun separated (separator parts)
  (let ((parts (remove nil parts)))
    (and parts
         (apply #'sql
                (format nil "~{~a~}" (cons (sql-text (first parts))
                                           (loop :for part :in (rest parts)
                                                 :collect separator :collect (sql-text part))))
                (params-of parts)))))

(defun all-of (parts)
  (let ((joined (separated " AND " parts)))
    (and joined (fragment "(~a)" joined))))

(defun any-of (parts)
  (let ((joined (separated " OR " parts)))
    (and joined (fragment "(~a)" joined))))

(defun in-list (values)
  (apply #'sql (format nil "(~{~*?~^, ~})" values) values))

(defun like-pattern (text &key prefix)
  (let ((escaped (with-output-to-string (out)
                   (loop :for c :across text
                         :do (when (member c '(#\% #\_ #\\)) (write-char #\\ out))
                             (write-char c out)))))
    (if prefix
        (format nil "~a%" escaped)
        (format nil "%~a%" escaped))))

(defun json-path (&rest names)
  (format nil "$~{.~a~}" names))

(defun json-at (column &rest names)
  (fragment "json_extract(~a, ~a)" column (bound (apply #'json-path names))))
