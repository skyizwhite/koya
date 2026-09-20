(defpackage #:koya-server/lib/query
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-field #:field-type #:field-many-p #:+system-fields+)
  (:import-from #:cl-ppcre
                #:scan-to-strings #:split)
  (:export #:query-error
           #:query-error-message
           #:parse-query
           #:make-query
           #:query-limit #:query-offset #:query-orders #:query-filters #:query-fields #:query-include
           #:build-where
           #:build-order-by
           #:+system-fields+))
(in-package #:koya-server/lib/query)

;;; Parsing of microCMS-compatible list query parameters and translation of
;;; filters/orders into SQL over the JSON data column.

(define-condition query-error (error)
  ((message :initarg :message :reader query-error-message))
  (:report (lambda (c s) (format s "Bad query: ~a" (query-error-message c)))))

(defun bad (fmt &rest args)
  (error 'query-error :message (apply #'format nil fmt args)))

(defparameter +default-limit+ 10)
(defparameter +max-limit+ 100)

(defstruct query
  (limit +default-limit+)
  (offset 0)
  orders    ; list of (name . :asc/:desc)
  filters   ; list of groups, each group a list of (name op value); groups are OR'ed, terms AND'ed
  fields    ; list of field names or NIL for all
  include)  ; list of reference paths to embed, each a list of field names (a.b -> ("a" "b"))

(defun param (params name)
  (let ((v (cdr (assoc name params :test #'string=))))
    (if (and (stringp v) (string= v "")) nil v)))

(defun parse-integer-param (params name default &key (min 0) max)
  (let ((raw (param params name)))
    (if (null raw)
        default
        (let ((n (handler-case (parse-integer raw) (error () (bad "~a must be an integer" name)))))
          (when (< n min) (bad "~a must be at least ~a" name min))
          (if (and max (> n max)) max n)))))

(defun split-csv (string)
  (remove "" (mapcar (lambda (s) (string-trim " " s)) (split "," string)) :test #'string=))

(defun parse-include (string)
  "include=tags,author.avatar -> ((\"tags\") (\"author\" \"avatar\"))"
  (mapcar (lambda (path) (remove "" (split "\\." path) :test #'string=)) (split-csv string)))

(defun parse-orders (string)
  (mapcar (lambda (item)
            (if (char= (char item 0) #\-)
                (cons (subseq item 1) :desc)
                (cons item :asc)))
          (split-csv string)))

(defun parse-term (term)
  (multiple-value-bind (match groups) (scan-to-strings "^([A-Za-z0-9_.]+)\\[([a-z_]+)\\](.*)$" term)
    (unless match (bad "malformed filter ~s" term))
    (list (aref groups 0) (aref groups 1) (aref groups 2))))

(defun parse-filters (string)
  "\"a[equals]1[and]b[exists][or]c[equals]2\" -> ((\"a\" ... ) (\"b\" ...)) groups OR'ed."
  (let ((groups '())
        (current '())
        (rest string))
    (loop
      (multiple-value-bind (match parts) (scan-to-strings "^(.*?)\\[(and|or)\\](.*)$" rest)
        (cond (match
               (push (parse-term (aref parts 0)) current)
               (when (string= (aref parts 1) "or")
                 (push (nreverse current) groups)
                 (setf current '()))
               (setf rest (aref parts 2)))
              (t
               (push (parse-term rest) current)
               (push (nreverse current) groups)
               (return)))))
    (nreverse groups)))

(defun parse-query (params)
  "Build a QUERY from ningle's params alist. Signals QUERY-ERROR on bad input."
  (make-query :limit (parse-integer-param params "limit" +default-limit+ :min 0 :max +max-limit+)
              :offset (parse-integer-param params "offset" 0)
              :orders (let ((o (param params "orders"))) (and o (parse-orders o)))
              :filters (let ((f (param params "filters"))) (and f (parse-filters f)))
              :fields (let ((f (param params "fields"))) (and f (split-csv f)))
              :include (let ((i (param params "include"))) (and i (parse-include i)))))

;;; --- SQL generation ---------------------------------------------------------

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
        (unless (model-field model name) (bad "unknown field ~s" name))
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
           (or (parse-number-strictly value) (bad "~a expects a number" name)))
          ((eq (field-type field) :boolean)
           (cond ((string= value "true") 1) ((string= value "false") 0) (t (bad "~a expects true or false" name))))
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
          (t (bad "unknown filter operator ~s" op)))))))

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
