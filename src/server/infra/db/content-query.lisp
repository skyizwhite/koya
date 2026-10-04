(defpackage #:koya-server/infra/db/content-query
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-field #:field-type #:field-many-p #:field-name #:field-fields)
  (:import-from #:koya-server/domain/query
                #:bad-query)
  (:import-from #:koya-server/domain/number
                #:parse-decimal)
  (:export #:build-where
           #:build-order-by))
(in-package #:koya-server/infra/db/content-query)

(defun system-column (name)
  (cond ((string= name "id") "id")
        ((string= name "createdAt") "created_at")
        ((string= name "updatedAt") "updated_at")
        ((string= name "publishedAt") "published_at")
        ((string= name "revisedAt") "revised_at")
        (t nil)))

(defun field-expr (name model column)
  (or (system-column name)
      (let ((field (or (model-field model name) (bad-query "unknown field ~s" name))))
        (when (eq (field-type field) :custom)
          (bad-query "~a is a custom field: only contains and not_contains read it" name))
        (format nil (if (eq (field-type field) :boolean) "COALESCE(json_extract(~a, '$.~a'), 0)" "json_extract(~a, '$.~a')")
                column name))))

(defun present-sql (expr many)
  (if many
      (format nil "COALESCE(json_array_length(~a), 0) > 0" expr)
      (format nil "(~a IS NOT NULL AND trim(~a, char(32, 9, 10, 13)) != '')" expr expr)))

(defun coerce-value (name model value)
  (let ((field (model-field model name)))
    (cond ((null field) value)
          ((eq (field-type field) :number)
           (or (parse-decimal value) (bad-query "~a expects a number" name)))
          ((eq (field-type field) :boolean)
           (cond ((string= value "true") 1) ((string= value "false") 0) (t (bad-query "~a expects true or false" name))))
          (t value))))

(defparameter +text-types+ '(:text :textarea :slug :richtext))

(defun inner-expr (outer inner column text-column)
  (format nil "json_extract(~a, '$.~a.~a')"
          (if (and text-column (eq (field-type inner) :richtext)) text-column column)
          (field-name outer) (field-name inner)))

(defun text-sql (name exprs op value)
  (let ((like (format nil "%~a%" (escape-like value))))
    (cond ((string= op "contains")
           (values (if exprs
                       (format nil "(~{~a~^ OR ~})"
                               (mapcar (lambda (e) (format nil "~a LIKE ? ESCAPE '\\'" e)) exprs))
                       "0")
                   (mapcar (constantly like) exprs)))
          ((string= op "not_contains")
           (values (if exprs
                       (format nil "(~{~a~^ AND ~})"
                               (mapcar (lambda (e) (format nil "(~a IS NULL OR ~a NOT LIKE ? ESCAPE '\\')" e e)) exprs))
                       "1")
                   (mapcar (constantly like) exprs)))
          (t (bad-query "~a is inside a custom field: only contains and not_contains read it" name)))))

(defun inside (model name)
  (let* ((dot (position #\. name))
         (outer (and dot (model-field model (subseq name 0 dot)))))
    (when (and outer (eq (field-type outer) :custom))
      (values outer (find (subseq name (1+ dot)) (field-fields outer) :key #'field-name :test #'string=)))))

(defun term-sql (term model column text-column)
  (destructuring-bind (name op value) term
    (let ((field (model-field model name)))
      (multiple-value-bind (outer inner) (inside model name)
        (cond ((and field (eq (field-type field) :custom))
               (text-sql name
                         (loop :for inner :in (field-fields field)
                               :when (member (field-type inner) +text-types+)
                                 :collect (inner-expr field inner column text-column))
                         op value))
              ((and outer inner (member (field-type inner) +text-types+))
               (text-sql name (list (inner-expr outer inner column text-column)) op value))
              (t (field-term-sql term model column text-column)))))))

(defun field-term-sql (term model column text-column)
  (destructuring-bind (name op value) term
    (let* ((field (model-field model name))
           (many (and field (field-many-p field)))
           (expr (field-expr name model column))
           (text (if (and field text-column (eq (field-type field) :richtext))
                     (format nil "json_extract(~a, '$.~a')" text-column name)
                     expr)))
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
                                       (values (format nil "~a LIKE ? ESCAPE '\\'" text) (list (format nil "%~a%" (escape-like value))))))
          ((string= op "not_contains") (if many
                                           (values (format nil "NOT EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ?)" expr) (list value))
                                           (values (format nil "(~a IS NULL OR ~a NOT LIKE ? ESCAPE '\\')" text text) (list (format nil "%~a%" (escape-like value))))))
          ((string= op "begins_with") (values (format nil "~a LIKE ? ESCAPE '\\'" text) (list (format nil "~a%" (escape-like value)))))
          ((string= op "exists") (values (present-sql expr many) '()))
          ((string= op "not_exists") (values (format nil "NOT ~a" (present-sql expr many)) '()))
          (t (bad-query "unknown filter operator ~s" op)))))))

(defun escape-like (string)
  (with-output-to-string (out)
    (loop :for c :across string
          :do (when (member c '(#\% #\_ #\\)) (write-char #\\ out))
              (write-char c out))))

(defun groups-sql (filters model column text-column)
  (let ((group-sqls '()) (params '()))
    (dolist (group filters)
      (let ((term-sqls '()))
        (dolist (term group)
          (multiple-value-bind (sql ps) (term-sql term model column text-column)
            (push sql term-sqls)
            (setf params (append params ps))))
        (push (format nil "(~{~a~^ AND ~})" (nreverse term-sqls)) group-sqls)))
    (values (format nil "(~{~a~^ OR ~})" (nreverse group-sqls)) params)))

(defun build-where (filters model column &key and text-column)
  (let ((sqls '()) (params '()))
    (dolist (set (list filters and))
      (when set
        (multiple-value-bind (sql ps) (groups-sql set model column text-column)
          (push sql sqls)
          (setf params (append params ps)))))
    (when sqls
      (values (format nil "~{~a~^ AND ~}" (nreverse sqls)) params))))

(defun build-order-by (orders model column)
  (if (null orders)
      "published_at DESC, created_at DESC, rowid DESC"
      (format nil "~{~a~^, ~}, rowid DESC"
              (mapcar (lambda (order)
                        (format nil "~a ~a" (field-expr (car order) model column)
                                (if (eq (cdr order) :desc) "DESC" "ASC")))
                      orders))))
