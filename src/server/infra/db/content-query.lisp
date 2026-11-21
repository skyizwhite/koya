(defpackage #:koya-server/infra/db/content-query
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-field #:field-type #:field-many-p #:field-name #:field-fields
                #:field-row-kinds #:custom-field-fields #:custom-field-name)
  (:import-from #:koya-server/domain/query
                #:bad-query)
  (:import-from #:koya-server/domain/number
                #:parse-decimal)
  (:import-from #:koya-server/infra/db/sql
                #:sql #:bound #:fragment #:separated #:all-of #:any-of #:like-pattern #:json-path #:json-at)
  (:export #:build-where
           #:build-order-by))
(in-package #:koya-server/infra/db/content-query)

(defun system-column (name)
  (cond ((string= name "id") (sql "id"))
        ((string= name "createdAt") (sql "created_at"))
        ((string= name "updatedAt") (sql "updated_at"))
        ((string= name "publishedAt") (sql "published_at"))
        ((string= name "revisedAt") (sql "revised_at"))
        (t nil)))

(defun field-expr (name model column)
  (or (system-column name)
      (let ((field (or (model-field model name) (bad-query "unknown field ~s" name))))
        (when (member (field-type field) '(:custom :repeater))
          (bad-query "~a holds fields of its own: only contains and not_contains read it" name))
        (if (eq (field-type field) :boolean)
            (fragment "COALESCE(~a, 0)" (json-at column name))
            (json-at column name)))))

(defun present-sql (expr many)
  (if many
      (fragment "COALESCE(json_array_length(~a), 0) > 0" expr)
      (fragment "(~a IS NOT NULL AND trim(~a, char(32, 9, 10, 13)) != '')" expr expr)))

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
  (json-at (if (and text-column (eq (field-type inner) :richtext)) text-column column)
           (field-name outer) (field-name inner)))

(defun like-sql (expr like)
  (fragment "~a LIKE ~a ESCAPE '\\'" expr like))

(defun not-like-sql (expr like)
  (fragment "(~a IS NULL OR ~a NOT LIKE ~a ESCAPE '\\')" expr expr like))

(defun text-sql (name exprs op value)
  (let ((like (bound (like-pattern value))))
    (cond ((string= op "contains")
           (or (any-of (mapcar (lambda (e) (like-sql e like)) exprs)) (sql "0")))
          ((string= op "not_contains")
           (or (all-of (mapcar (lambda (e) (not-like-sql e like)) exprs)) (sql "1")))
          (t (bad-query "~a is inside a custom field: only contains and not_contains read it" name)))))

(defun rows-matching-sql (field source like pick)
  (let* ((row (sql "each_row.value"))
         (kinds (loop :for kind :in (field-row-kinds field)
                      :for names := (mapcar #'field-name (remove-if-not pick (custom-field-fields kind)))
                      :when names
                        :collect (fragment "(~a = ~a AND ~a)"
                                           (json-at row "fieldId") (bound (custom-field-name kind))
                                           (any-of (mapcar (lambda (n) (like-sql (json-at row n) like)) names))))))
    (and kinds
         (fragment "EXISTS (SELECT 1 FROM json_each(~a, ~a) AS each_row WHERE ~a)"
                   source (bound (json-path (field-name field))) (any-of kinds)))))

(defun row-text-sql (field column text-column like)
  (or (any-of (list (rows-matching-sql field column like
                                       (lambda (f) (member (field-type f) '(:text :textarea :slug))))
                    (rows-matching-sql field (or text-column column) like
                                       (lambda (f) (eq (field-type f) :richtext)))))
      (sql "0")))

(defun repeater-term-sql (name field op value column text-column)
  (let ((rows (row-text-sql field column text-column (bound (like-pattern value)))))
    (cond ((string= op "contains") rows)
          ((string= op "not_contains") (fragment "NOT ~a" rows))
          (t (bad-query "~a is a repeater: only contains and not_contains read it" name)))))

(defun inside (model name)
  (let* ((dot (position #\. name))
         (outer (and dot (model-field model (subseq name 0 dot)))))
    (when (and outer (eq (field-type outer) :custom))
      (values outer (find (subseq name (1+ dot)) (field-fields outer) :key #'field-name :test #'string=)))))

(defun term-sql (term model column text-column)
  (destructuring-bind (name op value) term
    (let ((field (model-field model name)))
      (multiple-value-bind (outer inner) (inside model name)
        (cond ((and field (eq (field-type field) :repeater))
               (repeater-term-sql name field op value column text-column))
              ((and field (eq (field-type field) :custom))
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
                     (json-at text-column name)
                     expr)))
      (flet ((cmp (control)
               (fragment control expr (bound (coerce-value name model value))))
             (has (control)
               (fragment control expr (bound value))))
        (cond
          ((string= op "equals") (if many
                                     (has "EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ~a)")
                                     (cmp "~a = ~a")))
          ((string= op "not_equals") (if many
                                         (has "NOT EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ~a)")
                                         (fragment "(~a IS NULL OR ~a != ~a)" expr expr (bound (coerce-value name model value)))))
          ((string= op "less_than") (cmp "~a < ~a"))
          ((string= op "greater_than") (cmp "~a > ~a"))
          ((string= op "contains") (if many
                                       (has "EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ~a)")
                                       (like-sql text (bound (like-pattern value)))))
          ((string= op "not_contains") (if many
                                           (has "NOT EXISTS (SELECT 1 FROM json_each(~a) WHERE value = ~a)")
                                           (not-like-sql text (bound (like-pattern value)))))
          ((string= op "begins_with") (like-sql text (bound (like-pattern value :prefix t))))
          ((string= op "exists") (present-sql expr many))
          ((string= op "not_exists") (fragment "NOT ~a" (present-sql expr many)))
          (t (bad-query "unknown filter operator ~s" op)))))))

(defun groups-sql (filters model column text-column)
  (any-of (mapcar (lambda (group)
                    (all-of (mapcar (lambda (term) (term-sql term model column text-column)) group)))
                  filters)))

(defun build-where (filters model column &key and text-column)
  (separated " AND " (list (and filters (groups-sql filters model column text-column))
                           (and and (groups-sql and model column text-column)))))

(defun build-order-by (orders model column)
  (if (null orders)
      (sql "published_at DESC, created_at DESC, rowid DESC")
      (fragment "~a, rowid DESC"
                (separated ", " (mapcar (lambda (order)
                                          (fragment (if (eq (cdr order) :desc) "~a DESC" "~a ASC")
                                                    (field-expr (car order) model column)))
                                        orders)))))
