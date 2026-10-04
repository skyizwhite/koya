(defpackage #:koya-server/web/lib/forms
  (:use #:cl)
  (:import-from #:koya-core/schema #:model-fields #:field-name #:field-type #:field-many-p #:field-fields
                #:field-row-kinds #:custom-field-name #:custom-field-fields)
  (:import-from #:koya-core/json
                #:json-null)
  (:import-from #:cl-ppcre
                #:split)
  (:import-from #:koya-server/domain/number #:parse-decimal)
  (:import-from #:koya-server/domain/timezone #:iso->local-input #:local-input->iso)
  (:import-from #:koya-server/usecases/settings #:display-timezone)
  (:import-from #:koya-server/web/lib/http
                #:form-values #:form-list)
  (:export #:form->data
           #:field-param-name
           #:row-prefix
           #:form-value
           #:value->string
           #:number->string))
(in-package #:koya-server/web/lib/forms)

(defun field-param-name (field &optional parent)
  (format nil "f-~@[~a.~]~a" (and parent (if (stringp parent) parent (field-name parent))) (field-name field)))

(defun row-prefix (field key)
  (format nil "~a.~a" (field-name field) key))

(defun form-value (params name)
  (let ((v (first (form-values params name))))
    (and (stringp v) (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) v)))
         (string-trim '(#\Space #\Tab #\Newline #\Return) v))))

(defun split-ids (string)
  (remove "" (mapcar (lambda (s) (string-trim " " s)) (split "[,\\s]+" string)) :test #'string=))

(defun form->data (model params)
  (form->fields (model-fields model) params nil))

(defun form->fields (fields params parent)
  (let ((data (make-hash-table :test 'equal)))
    (dolist (field fields)
      (let* ((name (field-param-name field parent))
             (raw (form-value params name)))
        (case (field-type field)
          (:custom
           (when raw
             (setf (gethash (field-name field) data) (form->fields (field-fields field) params field))))
          (:repeater
           (let ((rows (loop :for key :in (form-list params name)
                             :for kind := (find (form-value params (format nil "~a.~a.fieldId" name key))
                                                (field-row-kinds field) :key #'custom-field-name :test #'equal)
                             :when kind
                               :collect (let ((row (form->fields (custom-field-fields kind) params (row-prefix field key))))
                                          (setf (gethash "fieldId" row) (custom-field-name kind))
                                          row))))
             (when rows (setf (gethash (field-name field) data) (coerce rows 'vector)))))
          (:boolean
           (setf (gethash (field-name field) data) (and raw t)))
          (:number
           (when raw (setf (gethash (field-name field) data) (or (parse-decimal raw) raw))))
          (:select
           (if (field-many-p field)
               (let ((values (form-list params name)))
                 (when values (setf (gethash (field-name field) data) (coerce values 'vector))))
               (when raw (setf (gethash (field-name field) data) raw))))
          ((:reference :media)
           (if (field-many-p field)
               (let ((ids (loop :for v :in (form-list params name) :append (split-ids v))))
                 (when ids (setf (gethash (field-name field) data) (coerce ids 'vector))))
               (when raw (setf (gethash (field-name field) data) raw))))
          (:datetime
           (when raw (setf (gethash (field-name field) data) (local-input->iso raw :timezone (display-timezone)))))
          ((:richtext :textarea)
           (when raw
             (setf (gethash (field-name field) data) (remove #\Return (first (form-values params name))))))
          (t
           (when raw (setf (gethash (field-name field) data) raw))))))
    data))

(defun number->string (n)
  (if (floatp n)
      (let ((*read-default-float-format* (type-of n))) (princ-to-string n))
      (princ-to-string n)))

(defun value->string (field value)
  (cond ((or (null value) (eq value json-null)) "")
        ((realp value) (number->string value))
        ((and (vectorp value) (not (stringp value)))
         (format nil "~{~a~^, ~}" (coerce value 'list)))
        ((eq (field-type field) :datetime)
         (if (stringp value) (iso->local-input value :timezone (display-timezone)) (princ-to-string value)))
        ((eq value t) "true")
        (t (princ-to-string value))))
