(defpackage #:koya-server/features/contents/labels
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-label #:model-name #:model-fields
                #:field-name #:field-type #:field-option)
  (:import-from #:koya-server/db/schema-store
                #:find-model)
  (:import-from #:koya-server/db/contents
                #:list-contents #:content-id #:content-data)
  (:import-from #:koya-server/lib/query
                #:make-query)
  (:export #:content-label
           #:reference-options
           #:reference-labels))
(in-package #:koya-server/features/contents/labels)

;;; What a content is called where it is shown or pointed at.

(defun content-label (content model)
  "What CONTENT is shown as: the value of the field MODEL declares as its :label,
else its id. No field is taken for a title unless the schema says so -- the
first text field of one model is another's subtitle."
  (let* ((label (model-label model))
         (data (and label (content-data content :draft t)))
         (value (and data (gethash label data))))
    (if (and (stringp value) (plusp (length value)))
        value
        (content-id content))))

(defun target-contents (space field)
  "(values CONTENTS MODEL) of the model a :reference FIELD points at, drafts
included: a reference may be set to one before it is published."
  (let ((target (find-model space (field-option field :model))))
    (when target
      (values (list-contents space (model-name target) target (make-query :limit 1000) :status :all)
              target))))

(defun reference-options (space field)
  "Selectable contents of FIELD's target model as (id . label), sorted by label."
  (when (eq (field-type field) :reference)
    (multiple-value-bind (contents target) (target-contents space field)
      (sort (mapcar (lambda (content) (cons (content-id content) (content-label content target))) contents)
            #'string-lessp :key #'cdr))))

(defun reference-labels (space model)
  "Field name -> hash of referenced id -> label, for every reference field of MODEL."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) table)
      (when (eq (field-type field) :reference)
        (let ((targets (make-hash-table :test 'equal)))
          (multiple-value-bind (contents target) (target-contents space field)
            (dolist (content contents)
              (setf (gethash (content-id content) targets) (content-label content target))))
          (setf (gethash (field-name field) table) targets))))))
