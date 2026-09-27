(defpackage #:koya-server/web/forms
  (:use #:cl)
  (:import-from #:koya-core/schema #:model-fields #:field-name #:field-type #:field-many-p)
  (:import-from #:koya-core/json
                #:json-null)
  (:import-from #:koya-core/validate
                #:blank-for-field-p)
  (:import-from #:cl-ppcre
                #:split)
  (:import-from #:koya-server/domain/number #:parse-decimal)
  (:import-from #:koya-server/domain/timezone #:iso->local-input #:local-input->iso)
  (:import-from #:koya-server/usecases/settings #:display-timezone)
  (:import-from #:koya-server/web/http
                #:form-values)
  (:export #:form->data
           #:field-param-name
           #:form-value
           #:value->string
           #:number->string))
(in-package #:koya-server/web/forms)

(defun field-param-name (field)
  (format nil "f-~a" (field-name field)))

(defun form-value (params name)
  (let ((v (first (form-values params name))))
    (and (stringp v) (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) v)))
         (string-trim '(#\Space #\Tab #\Newline #\Return) v))))

(defun split-ids (string)
  (remove "" (mapcar (lambda (s) (string-trim " " s)) (split "[,\\s]+" string)) :test #'string=))

(defun form->data (model params)
  (let ((data (make-hash-table :test 'equal)))
    (dolist (field (model-fields model))
      (let* ((name (field-param-name field))
             (raw (form-value params name)))
        (case (field-type field)
          (:boolean
           (setf (gethash (field-name field) data) (and raw t)))
          (:number
           (when raw (setf (gethash (field-name field) data) (or (parse-decimal raw) raw))))
          (:select
           (if (field-many-p field)
               (let ((values (remove "" (form-values params name) :test #'string=)))
                 (when values (setf (gethash (field-name field) data) (coerce values 'vector))))
               (when raw (setf (gethash (field-name field) data) raw))))
          ((:reference :media)
           (if (field-many-p field)
               (let ((ids (loop :for v :in (form-values params name) :append (split-ids v))))
                 (when ids (setf (gethash (field-name field) data) (coerce ids 'vector))))
               (when raw (setf (gethash (field-name field) data) raw))))
          (:datetime
           (when raw (setf (gethash (field-name field) data) (local-input->iso raw :timezone (display-timezone)))))
          (:richtext
           (let ((html (and raw (remove #\Return (first (form-values params name))))))
             (when (and html (not (blank-for-field-p field html)))
               (setf (gethash (field-name field) data) html))))
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

