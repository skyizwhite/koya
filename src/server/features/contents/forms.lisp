(defpackage #:koya-server/features/contents/forms
  (:use #:cl)
  (:import-from #:koya/core/schema #:model-fields #:field-name #:field-type #:field-many-p)
  (:import-from #:koya/core/json
                #:json-null)
  (:import-from #:cl-ppcre
                #:split #:scan)
  (:import-from #:koya-server/domain/timezone #:iso->local-input #:local-input->iso)
  (:import-from #:koya-server/lib/timezone #:display-timezone)
  (:import-from #:koya-server/lib/http
                #:form-values)
  (:export #:form->data
           #:field-param-name
           #:form-value
           #:value->string
           #:number->string))
(in-package #:koya-server/features/contents/forms)

;;; Conversion between HTML form submissions and content data objects.

(defun field-param-name (field)
  (format nil "f-~a" (field-name field)))

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
           (when raw (setf (gethash (field-name field) data) (local-input->iso raw :timezone (display-timezone)))))
          (:richtext
           ;; stored as the editor sent it (see koya-editor.js), but for the CRLF
           ;; a form submission turns its line breaks into -- not trimmed, as the
           ;; other fields are, or an untouched field would lose the whitespace
           ;; around it. Quill reports an empty document as <p></p> or <p><br></p>.
           (let ((html (and raw (remove #\Return (first (form-values params name))))))
             (when (and html (not (scan "^(?:<p>(?:<br\\s*/?>)?</p>\\s*)*$" html)))
               (setf (gethash (field-name field) data) html))))
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
         (if (stringp value) (iso->local-input value :timezone (display-timezone)) (princ-to-string value)))
        ((eq value t) "true")
        (t (princ-to-string value))))

