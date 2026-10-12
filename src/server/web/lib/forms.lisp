(defpackage #:koya-server/web/lib/forms
  (:use #:cl)
  (:import-from #:koya-core/schema #:model-fields #:field-name #:field-key #:field-type #:field-many-p #:field-fields
                #:field-row-kind #:custom-field-name #:custom-field-fields)
  (:import-from #:koya-core/json
                #:json-array-p)
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

(defun form-field-value (field params parent)
  (let* ((name (field-param-name field parent))
         (raw (form-value params name)))
    (case (field-type field)
      (:custom
       (when raw
         (values (form->fields (field-fields field) params field) t)))
      (:repeater
       (let ((rows (loop :for key :in (form-list params name)
                         :for kind := (field-row-kind field (form-value params (format nil "~a.~a.fieldId" name key)))
                         :when kind
                           :collect (append (form->fields (custom-field-fields kind) params (row-prefix field key))
                                            (list :field-id (custom-field-name kind))))))
         (when rows (values (coerce rows 'vector) t))))
      (:boolean
       (values (and raw t) t))
      (:number
       (when raw (values (or (parse-decimal raw) raw) t)))
      (:select
       (if (field-many-p field)
           (let ((values (form-list params name)))
             (when values (values (coerce values 'vector) t)))
           (when raw (values raw t))))
      ((:reference :media)
       (if (field-many-p field)
           (let ((ids (loop :for v :in (form-list params name) :append (split-ids v))))
             (when ids (values (coerce ids 'vector) t)))
           (when raw (values raw t))))
      (:datetime
       (when raw (values (local-input->iso raw :timezone (display-timezone)) t)))
      ((:richtext :textarea)
       (when raw
         (values (remove #\Return (first (form-values params name))) t)))
      (t
       (when raw (values raw t))))))

(defun form->fields (fields params parent)
  (loop :for field :in fields
        :append (multiple-value-bind (value given) (form-field-value field params parent)
                  (and given (list (field-key field) value)))))

(defun number->string (n)
  (if (floatp n)
      (let ((*read-default-float-format* (type-of n))) (princ-to-string n))
      (princ-to-string n)))

(defun value->string (field value)
  (cond ((or (null value) (eq value :null)) "")
        ((realp value) (number->string value))
        ((json-array-p value)
         (format nil "~{~a~^, ~}" (coerce value 'list)))
        ((eq (field-type field) :datetime)
         (if (stringp value) (iso->local-input value :timezone (display-timezone)) (princ-to-string value)))
        ((eq value t) "true")
        (t (princ-to-string value))))
