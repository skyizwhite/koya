(defpackage #:koya-server/infra/db/content-query
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-field #:field-type #:field-many-p)
  (:import-from #:koya-server/domain/query
                #:bad-query)
  (:export #:build-where
           #:build-order-by))
(in-package #:koya-server/infra/db/content-query)

;;; A query's filters and orders as SQL over a JSON data column.

(defun system-column (name)
  (cond ((string= name "id") "id")
        ((string= name "createdAt") "created_at")
        ((string= name "updatedAt") "updated_at")
        ((string= name "publishedAt") "published_at")
        ((string= name "revisedAt") "revised_at")
        (t nil)))

(defun field-expr (name model column)
  "SQL expression selecting field NAME. System fields are real columns, the rest
live inside the JSON data column."
  (or (system-column name)
      (progn
        (unless (model-field model name) (bad-query "unknown field ~s" name))
        (format nil "json_extract(~a, '$.~a')" column name))))

(defun parse-number-strictly (string)
  "STRING as a real number, or NIL. The reader runs with *read-eval* off and standard
syntax, and the whole string must be one number: filter values come from the network."
  (handler-case
      (with-standard-io-syntax
        (let ((*read-eval* nil) (*read-default-float-format* 'double-float))
          (multiple-value-bind (n end) (read-from-string string)
            (and (realp n) (= end (length string)) n))))
    (error () nil)))

(defun coerce-value (name model value)
  (let ((field (model-field model name)))
    (cond ((null field) value)
          ((eq (field-type field) :number)
           (or (parse-number-strictly value) (bad-query "~a expects a number" name)))
          ((eq (field-type field) :boolean)
           (cond ((string= value "true") 1) ((string= value "false") 0) (t (bad-query "~a expects true or false" name))))
          (t value))))

(defun term-sql (term model column)
  (destructuring-bind (name op value) term
    (let* ((field (model-field model name))
           (many (and field (field-many-p field)))
           (expr (field-expr name model column)))
      (flet ((cmp (operator)
               (values (format nil "~a ~a ?" expr operator) (list (coerce-value name model value)))))
        (cond
          ((string= op "equals") (if many
                                     (values (format nil "EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ?)" expr) (list value))
                                     (cmp "=")))
          ((string= op "not_equals") (if many
                                         (values (format nil "NOT EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ?)" expr) (list value))
                                         (values (format nil "(~a IS NULL OR ~a != ?)" expr expr) (list (coerce-value name model value)))))
          ((string= op "less_than") (cmp "<"))
          ((string= op "greater_than") (cmp ">"))
          ((string= op "contains") (if many
                                       (values (format nil "EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ?)" expr) (list value))
                                       (values (format nil "~a LIKE ? ESCAPE '\\'" expr) (list (format nil "%~a%" (escape-like value))))))
          ((string= op "not_contains") (if many
                                           (values (format nil "NOT EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ?)" expr) (list value))
                                           (values (format nil "(~a IS NULL OR ~a NOT LIKE ? ESCAPE '\\')" expr expr) (list (format nil "%~a%" (escape-like value))))))
          ((string= op "begins_with") (values (format nil "~a LIKE ? ESCAPE '\\'" expr) (list (format nil "~a%" (escape-like value)))))
          ((string= op "exists") (values (format nil "~a IS NOT NULL" expr) '()))
          ((string= op "not_exists") (values (format nil "~a IS NULL" expr) '()))
          (t (bad-query "unknown filter operator ~s" op)))))))

(defun escape-like (string)
  (with-output-to-string (out)
    (loop :for c :across string
          :do (when (member c '(#\% #\_ #\\)) (write-char #\\ out))
              (write-char c out))))

(defun build-where (filters model column)
  "Return (values SQL PARAMS) for FILTERS (as parsed by PARSE-FILTERS), or (values NIL NIL)."
  (when filters
    (let ((group-sqls '()) (params '()))
      (dolist (group filters)
        (let ((term-sqls '()))
          (dolist (term group)
            (multiple-value-bind (sql ps) (term-sql term model column)
              (push sql term-sqls)
              (setf params (append params ps))))
          (push (format nil "(~{~a~^ AND ~})" (nreverse term-sqls)) group-sqls)))
      (values (format nil "(~{~a~^ OR ~})" (nreverse group-sqls)) params))))

(defun build-order-by (orders model column)
  "ORDER BY clause body for ORDERS, defaulting to newest published first."
  (if (null orders)
      "published_at DESC, created_at DESC, rowid DESC"
      (format nil "~{~a~^, ~}, rowid DESC"
              (mapcar (lambda (order)
                        (format nil "~a ~a" (field-expr (car order) model column)
                                (if (eq (cdr order) :desc) "DESC" "ASC")))
                      orders))))
