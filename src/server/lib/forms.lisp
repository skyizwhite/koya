(defpackage #:koya-server/lib/forms
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-fields #:field-name #:field-type #:field-option #:field-many-p)
  (:import-from #:koya/core/json
                #:json-null)
  (:import-from #:cl-ppcre
                #:regex-replace-all #:split #:scan #:quote-meta-chars)
  (:import-from #:koya-server/lib/env
                #:base-url)
  (:import-from #:koya-server/lib/timezone
                #:iso->local-input #:local-input->iso)
  (:export #:form->data
           #:field-param-name
           #:form-values
           #:form-value
           #:slugify
           #:value->string
           #:number->string
           #:normalize-richtext))
(in-package #:koya-server/lib/forms)

;;; Conversion between HTML form submissions and content data objects.

(defun field-param-name (field)
  (format nil "f-~a" (field-name field)))

(defun form-values (params name)
  "All values submitted under NAME (checkbox groups repeat the name)."
  (loop :for (k . v) :in params
        :when (and (stringp k) (string= k name)) :collect v))

(defun form-value (params name)
  (let ((v (first (form-values params name))))
    (and (stringp v) (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) v)))
         (string-trim '(#\Space #\Tab #\Newline #\Return) v))))

(defun parse-number (string)
  (handler-case
      (let* ((*read-default-float-format* 'double-float)
             (n (with-standard-io-syntax
                  (let ((*read-eval* nil) (*read-default-float-format* 'double-float))
                    (read-from-string string)))))
        (if (realp n) n string))
    (error () string)))

(defun split-ids (string)
  (remove "" (mapcar (lambda (s) (string-trim " " s)) (split "[,\\s]+" string)) :test #'string=))

(defparameter +block-close-pattern+
  "(</(?:p|h[1-6]|ul|ol|li|blockquote|pre|table|thead|tbody|tr|figure)>|<hr\\s*/?>)\\s*"
  "Block-level boundaries after which the stored HTML gets a newline.")

(defun normalize-richtext (html)
  "Tidy rich text HTML coming from the editor: an empty paragraph becomes a visible
blank line and every block element ends with a newline, so the stored source
stays readable and diffs cleanly."
  (let* ((html (regex-replace-all "<p>\\s*</p>" html "<p><br></p>"))
         (html (regex-replace-all +block-close-pattern+ html (format nil "\\1~%")))
         ;; our own media is stored by path; the delivery API makes it absolute again
         (html (regex-replace-all (format nil "(src|href)=\"~a/media/" (quote-meta-chars (string-right-trim "/" (base-url))))
                                  html "\\1=\"/media/")))
    (string-trim '(#\Newline #\Return #\Space) html)))

(defun form->data (model params)
  "Build a content data object from PARAMS for MODEL. Blank inputs are omitted,
except booleans which are always present (unchecked = false)."
  (let ((data (make-hash-table :test 'equal)))
    (dolist (field (model-fields model))
      (let* ((name (field-param-name field))
             (raw (form-value params name)))
        (case (field-type field)
          (:boolean
           (setf (gethash (field-name field) data) (and raw t)))
          (:number
           (when raw (setf (gethash (field-name field) data) (parse-number raw))))
          (:select
           (if (field-many-p field)
               (let ((values (remove "" (form-values params name) :test #'string=)))
                 (when values (setf (gethash (field-name field) data) (coerce values 'vector))))
               (when raw (setf (gethash (field-name field) data) raw))))
          ((:reference :media)
           (if (field-many-p field)
               ;; a multiple select repeats the name; a text input separates ids with commas
               (let ((ids (loop :for v :in (form-values params name) :append (split-ids v))))
                 (when ids (setf (gethash (field-name field) data) (coerce ids 'vector))))
               (when raw (setf (gethash (field-name field) data) raw))))
          (:datetime
           ;; datetime-local gives 2026-09-20T10:00 in the display zone; stored as UTC
           (when raw (setf (gethash (field-name field) data) (local-input->iso raw))))
          (:richtext
           ;; Quill reports an empty document as <p></p> or <p><br></p>.
           (when (and raw (not (scan "^(?:<p>(?:<br\\s*/?>)?</p>\\s*)*$" raw)))
             (setf (gethash (field-name field) data) (normalize-richtext raw))))
          (t
           (when raw (setf (gethash (field-name field) data) raw))))))
    data))

(defun number->string (n)
  "3 -> \"3\", 1.5d0 -> \"1.5\": no exponent marker, so <input type=number> accepts it."
  (if (floatp n)
      (let ((*read-default-float-format* (type-of n))) (princ-to-string n))
      (princ-to-string n)))

(defun value->string (field value)
  "Render a stored VALUE of FIELD as the string shown in its input."
  (cond ((or (null value) (eq value json-null)) "")
        ((realp value) (number->string value))
        ((and (vectorp value) (not (stringp value)))
         (format nil "~{~a~^, ~}" (coerce value 'list)))
        ((eq (field-type field) :datetime)
         ;; 2026-09-20T01:00:00.000Z -> 2026-09-20T10:00 for datetime-local, in the display zone
         (if (stringp value) (iso->local-input value) (princ-to-string value)))
        ((eq value t) "true")
        (t (princ-to-string value))))

(defun slugify (string)
  "Lowercase ASCII slug: letters, digits and single hyphens."
  (let* ((lower (string-downcase string))
         (dashed (regex-replace-all "[^a-z0-9]+" lower "-")))
    (string-trim "-" dashed)))
