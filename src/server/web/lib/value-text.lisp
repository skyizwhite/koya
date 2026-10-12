(defpackage #:koya-server/web/lib/value-text
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:field-type #:field-name #:field-fields #:row-kind #:custom-field-name #:custom-field-fields
                #:field-value)
  (:import-from #:koya-core/json #:json-array-p)
  (:import-from #:koya-core/validate #:blank-value-p)
  (:import-from #:koya-server/domain/html #:html-text)
  (:import-from #:koya-server/web/lib/display #:short-time)
  (:import-from #:koya-server/web/lib/forms #:number->string)
  (:export #:value-text))
(in-package #:koya-server/web/lib/value-text)

(defun scalar-text (field value label)
  (case (field-type field)
    ((:reference :media) (funcall label field value))
    (:richtext (if (stringp value)
                   (let ((text (html-text value))) (and (plusp (length text)) text))
                   (princ-to-string value)))
    (:datetime (short-time value))
    (:boolean (if value "Yes" "No"))
    (:number (if (realp value) (number->string value) (princ-to-string value)))
    (t (if (eq value t) "Yes" (princ-to-string value)))))

(defun fields-text (fields value separator label)
  (let ((texts (loop :for inner :in fields
                     :for (inner-value found) := (multiple-value-list (field-value value inner))
                     :for text := (value-text inner inner-value found label)
                     :when text :collect (format nil "~a: ~a" (field-name inner) text))))
    (and texts (format nil (format nil "~~{~~a~~^~a~~}" separator) texts))))

(defun rows-text (field value label)
  (let ((texts (loop :for row :across value
                     :for kind := (row-kind field row)
                     :when kind
                       :collect (format nil "~a: ~a" (custom-field-name kind)
                                        (or (fields-text (custom-field-fields kind) row "; " label) "")))))
    (and texts (format nil "~{~a~^~%~}" texts))))

(defun value-text (field value found label)
  (cond ((eq (field-type field) :boolean)
         (and found (not (eq value :null)) (scalar-text field value label)))
        ((and found (eq (field-type field) :custom) (listp value))
         (fields-text (field-fields field) value (string #\Newline) label))
        ((or (not found) (blank-value-p value)) nil)
        ((eq (field-type field) :repeater)
         (and (json-array-p value) (rows-text field value label)))
        ((json-array-p value)
         (let ((texts (remove nil (map 'list (lambda (v) (scalar-text field v label)) value))))
           (and texts (format nil "~{~a~^, ~}" texts))))
        (t (scalar-text field value label))))
