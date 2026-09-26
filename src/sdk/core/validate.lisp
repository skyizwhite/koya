(defpackage #:koya/core/validate
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-fields
                #:field-name
                #:field-type
                #:field-option
                #:field-required-p
                #:field-many-p)
  (:import-from #:koya/core/json
                #:json-null-p
                #:json-array-p)
  (:import-from #:cl-ppcre
                #:scan)
  (:import-from #:local-time
                #:parse-timestring)
  (:export #:validate-content
           #:validation-error
           #:validation-error-errors
           #:blank-value-p
           #:content-id-p))
(in-package #:koya/core/validate)

;;; Validation of content data (a JSON object with camelCase keys) against a
;;; model. Returns a list of error plists: (:field NAME :code CODE :message MSG).

(define-condition validation-error (error)
  ((errors :initarg :errors :reader validation-error-errors))
  (:report (lambda (c s)
             (format s "Validation failed:~{~% ~a~}"
                     (mapcar (lambda (e) (format nil "~a: ~a" (getf e :field) (getf e :message)))
                             (validation-error-errors c))))))

(defun blank-value-p (value)
  (or (null value)
      (json-null-p value)
      (and (stringp value) (zerop (length (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
      (and (json-array-p value) (zerop (length value)))))

(defun empty-richtext-p (value)
  "True for the HTML an editor leaves behind an emptied document: nothing but
empty paragraphs, each holding at most a line break, as Quill writes <p><br></p>."
  (and (stringp value) (scan "^\\s*(?:<p>(?:<br\\s*/?>)?</p>\\s*)*$" value) t))

(defun blank-for-field-p (field value)
  "Blank means 'no value given': null, a whitespace-only string, an empty array
on a :many field, and on a :richtext field the HTML of an emptied document. JSON
false (NIL) is a value, so a text field set to false is a type error rather than
an omission; the same goes for [] on a single-value field."
  (or (json-null-p value)
      (and (stringp value) (zerop (length (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
      (and (field-many-p field) (json-array-p value) (zerop (length value)))
      (and (eq (field-type field) :richtext) (empty-richtext-p value))))

(defun err (field code fmt &rest args)
  (list :field (field-name field) :code code :message (apply #'format nil fmt args)))

(defun parses-as-time-p (string)
  "True when local-time accepts STRING. :fail-on-error only covers syntax; a date
that does not exist on the calendar (2026-02-30) signals, so that is caught too."
  (handler-case (and (parse-timestring string :fail-on-error nil) t)
    (error () nil)))

(defun date-string-p (value)
  (and (stringp value)
       (scan "^\\d{4}-\\d{2}-\\d{2}\\z" value)
       (parses-as-time-p value)))

(defun datetime-string-p (value)
  "ISO 8601 date and time with an explicit zone: 2026-09-20T10:00:00.000Z or ...+09:00."
  (and (stringp value)
       (scan "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d+)?)?(?:Z|[+-]\\d{2}:\\d{2})\\z" value)
       (parses-as-time-p value)))

(defun content-id-p (value)
  "Content ids: 1-64 URL-safe characters (ULIDs, or ids carried over from another system)."
  (and (stringp value) (scan "^[A-Za-z0-9_-]{1,64}\\z" value) t))

(defun slug-string-p (value)
  (and (stringp value) (scan "^[a-z0-9]+(?:-[a-z0-9]+)*\\z" value) t))

(defun check-string (field value &key (code "type") (what "a string"))
  (cond ((not (stringp value))
         (list (err field code "must be ~a" what)))
        (t
         (let ((max (field-option field :max-length))
               (pattern (field-option field :pattern))
               (errors '()))
           (when (and max (> (length value) max))
             (push (err field "max_length" "must be at most ~a characters" max) errors))
           (when (and pattern (not (scan pattern value)))
             (push (err field "pattern" "must match ~a" pattern) errors))
           errors))))

(defun check-one (field value)
  "Validate a single (non-many) VALUE for FIELD."
  (ecase (field-type field)
    ((:text :textarea :richtext)
     (check-string field value))
    (:slug
     (append (check-string field value)
             (unless (slug-string-p value)
               (list (err field "slug" "must be a URL slug (lowercase letters, digits, hyphens)")))))
    (:number
     (cond ((not (realp value)) (list (err field "type" "must be a number")))
           (t (let ((min (field-option field :min))
                    (max (field-option field :max))
                    (errors '()))
                (when (and (field-option field :integer) (not (integerp value)))
                  (push (err field "integer" "must be an integer") errors))
                (when (and min (< value min)) (push (err field "min" "must be at least ~a" min) errors))
                (when (and max (> value max)) (push (err field "max" "must be at most ~a" max) errors))
                errors))))
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
     (unless (and (stringp value) (member value (field-option field :options) :test #'string=))
       (list (err field "option" "must be one of ~{~a~^, ~}" (field-option field :options)))))
    ((:media :reference)
     (unless (content-id-p value)
       (list (err field "type" "must be an id"))))))

(defun check-value (field value)
  (if (field-many-p field)
      (if (json-array-p value)
          (loop :for v :across value :append (check-one field v))
          (list (err field "type" "must be an array")))
      (check-one field value)))

(defun validate-content (model data &key partial)
  "Validate DATA (hash table, camelCase keys) against MODEL. With PARTIAL,
missing fields are not treated as errors (for PATCH-style updates).
Returns a list of error plists; empty means valid."
  (let ((errors '())
        (known (mapcar #'field-name (model-fields model))))
    (maphash (lambda (key value)
               (declare (ignore value))
               (unless (member key known :test #'string=)
                 (push (list :field key :code "unknown_field" :message "is not a field of this model") errors)))
             data)
    (dolist (field (model-fields model))
      (multiple-value-bind (value found) (gethash (field-name field) data)
        (cond ((and (not found) partial) nil)
              ((not found)
               (when (and (field-required-p field) (not (eq (field-type field) :boolean)))
                 (push (err field "required" "is required") errors)))
              ((blank-for-field-p field value)
               (when (and (field-required-p field) (not (eq (field-type field) :boolean)))
                 (push (err field "required" "is required") errors)))
              (t (setf errors (append (reverse (check-value field value)) errors))))))
    (nreverse errors)))
