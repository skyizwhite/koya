(defpackage #:koya-core/validate
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-fields
                #:field-name
                #:field-key
                #:field-value
                #:field-type
                #:field-option
                #:field-required-p
                #:field-many-p
                #:field-type-options
                #:row-kind
                #:field-fields
                #:custom-field-name
                #:field-row-kinds
                #:field-row-kind
                #:custom-field-fields
                #:row-field-id
                #:row-fields
                #:key-name)
  (:import-from #:koya-core/json
                #:json-array-p)
  (:import-from #:cl-ppcre
                #:scan)
  (:import-from #:koya-core/time
                #:parse-iso)
  (:export #:validate-content
           #:fitted-shape
           #:validation-error
           #:validation-error-errors
           #:blank-value-p
           #:blank-for-field-p
           #:datetime-string-p
           #:content-id-p))
(in-package #:koya-core/validate)

(define-condition validation-error (error)
  ((errors :initarg :errors :reader validation-error-errors))
  (:report (lambda (c s)
             (format s "Validation failed:~{~% ~a~}"
                     (mapcar (lambda (e) (format nil "~a: ~a" (getf e :field) (getf e :message)))
                             (validation-error-errors c))))))

(defun blank-value-p (value)
  (or (null value)
      (eq value :null)
      (and (stringp value) (zerop (length (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
      (and (json-array-p value) (zerop (length value)))))

(defun blank-for-field-p (field value)
  (or (eq value :null)
      (and (stringp value) (zerop (length (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
      (and (or (field-many-p field) (eq (field-type field) :repeater)) (json-array-p value) (zerop (length value)))))

(defun err (field code fmt &rest args)
  (list :field (field-name field) :code code :message (apply #'format nil fmt args)))

(defun date-string-p (value)
  (and (stringp value)
       (scan "^\\d{4}-\\d{2}-\\d{2}\\z" value)
       (parse-iso value)
       t))

(defun datetime-string-p (value)
  (and (stringp value)
       (scan "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d+)?)?(?:Z|[+-]\\d{2}:\\d{2})\\z" value)
       (parse-iso value)
       t))

(defun content-id-p (value)
  (and (stringp value) (scan "^[A-Za-z0-9_-]{1,64}\\z" value) t))

(defun slug-string-p (value)
  (and (stringp value) (scan "^[a-z0-9]+(?:-[a-z0-9]+)*\\z" value) t))

(defun string-option-errors (field value)
  (let ((max (field-option field :max-length))
        (pattern (field-option field :pattern))
        (errors '()))
    (when (and max (> (length value) max))
      (push (err field "max_length" "must be at most ~a characters" max) errors))
    (when (and pattern (not (scan pattern value)))
      (push (err field "pattern" "must match ~a" pattern) errors))
    errors))

(defun number-option-errors (field value)
  (let ((min (field-option field :min))
        (max (field-option field :max))
        (errors '()))
    (when (and (field-option field :integer) (not (integerp value)))
      (push (err field "integer" "must be an integer") errors))
    (when (and min (< value min)) (push (err field "min" "must be at least ~a" min) errors))
    (when (and max (> value max)) (push (err field "max" "must be at most ~a" max) errors))
    errors))

(defun option-error (field)
  (err field "option" "must be one of ~{~a~^, ~}" (field-option field :options)))

(defun string-type-errors (field value)
  (unless (stringp value) (list (err field "type" "must be a string"))))

(defun type-errors (field value)
  (ecase (field-type field)
    ((:text :textarea :richtext)
     (string-type-errors field value))
    (:slug
     (append (string-type-errors field value)
             (unless (slug-string-p value)
               (list (err field "slug" "must be a URL slug (lowercase letters, digits, hyphens)")))))
    (:number
     (unless (realp value) (list (err field "type" "must be a number"))))
    (:boolean
     (unless (member value '(t nil))
       (list (err field "type" "must be a boolean"))))
    (:date
     (unless (date-string-p value)
       (list (err field "type" "must be a date (YYYY-MM-DD)"))))
    (:datetime
     (unless (datetime-string-p value)
       (list (err field "type" "must be an ISO 8601 datetime"))))
    (:select
     (unless (stringp value) (list (option-error field))))
    ((:media :reference)
     (unless (content-id-p value)
       (list (err field "type" "must be an id"))))))

(defun option-errors (field value)
  (case (field-type field)
    ((:text :textarea :richtext :slug)
     (when (stringp value) (string-option-errors field value)))
    (:number
     (when (realp value) (number-option-errors field value)))
    (:select
     (when (and (stringp value) (not (member value (field-option field :options) :test #'string=)))
       (list (option-error field))))))

(defun check-one (field value)
  (append (option-errors field value) (type-errors field value)))

(defun inside (path errors)
  (mapcar (lambda (e) (list* :field (format nil "~a.~a" path (getf e :field)) (rest (rest e))))
          errors))

(defun check-row (field index row)
  (let ((path (format nil "~a[~a]" (field-name field) index)))
    (if (not (listp row))
        (list (list :field path :code "type" :message "must be an object"))
        (let ((kind (field-row-kind field (row-field-id row))))
          (if (null kind)
              (list (list :field path :code "custom_field"
                          :message (format nil "must name its custom field in fieldId, one of ~{~a~^, ~}"
                                           (mapcar #'custom-field-name (field-row-kinds field)))))
              (inside path (validate-fields (custom-field-fields kind) (row-fields row) nil)))))))

(defun check-value (field value)
  (case (field-type field)
    (:custom
     (if (listp value)
         (inside (field-name field) (validate-fields (field-fields field) value nil))
         (list (err field "type" "must be an object"))))
    (:repeater
     (if (json-array-p value)
         (loop :for row :across value :for index :from 0 :append (check-row field index row))
         (list (err field "type" "must be an array"))))
    (t (check-many field value))))

(defun check-many (field value)
  (if (field-many-p field)
      (if (json-array-p value)
          (loop :for v :across value :append (check-one field v))
          (list (err field "type" "must be an array")))
      (check-one field value)))

(defun validate-content (model data &key partial)
  (validate-fields (model-fields model) data partial))

(defun validate-fields (fields data partial)
  (let ((errors '())
        (known (mapcar #'field-key fields)))
    (loop :for key :in data :by #'cddr
          :unless (member key known :test #'eq)
            :do (push (list :field (key-name key) :code "unknown_field" :message "is not a field of this model") errors))
    (dolist (field fields)
      (multiple-value-bind (value found) (field-value data field)
        (cond ((and (not found) partial) nil)
              ((not found)
               (when (and (field-required-p field) (not (eq (field-type field) :boolean)))
                 (push (err field "required" "is required") errors)))
              ((blank-for-field-p field value)
               (when (and (field-required-p field) (not (eq (field-type field) :boolean)))
                 (push (err field "required" "is required") errors)))
              (t (setf errors (append (reverse (check-value field value)) errors))))))
    (nreverse errors)))

(defun fitted-shape (model data)
  (fitted-fields (model-fields model) data))

(defun fitted-fields (fields data)
  (loop :for field :in fields
        :append (multiple-value-bind (value found) (field-value data field)
                  (when found
                    (multiple-value-bind (fitted fits) (fitted-value field value)
                      (when fits (list (field-key field) fitted)))))))

(defun fitted-rows (field rows)
  (coerce (loop :for row :across rows
                :for kind := (row-kind field row)
                :when kind
                  :collect (append (fitted-fields (custom-field-fields kind) row)
                                   (list :field-id (row-field-id row))))
          'vector))

(defun fitted-value (field value)
  (cond ((eq value :null) (values nil nil))
        ((eq (field-type field) :custom)
         (if (listp value) (values (fitted-fields (field-fields field) value) t) (values nil nil)))
        ((eq (field-type field) :repeater)
         (if (json-array-p value) (values (fitted-rows field value) t) (values nil nil)))
        ((json-array-p value)
         (if (member :many (field-type-options (field-type field)))
             (values (remove-if (lambda (v) (type-errors field v)) value) t)
             (values nil nil)))
        ((type-errors field value) (values nil nil))
        (t (values value t))))
