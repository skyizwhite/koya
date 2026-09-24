(defpackage #:koya-server/features/contents/labels
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-label #:model-name #:model-fields
                #:field-name #:field-type #:field-option)
  (:import-from #:koya-server/db/schema-store
                #:find-model)
  (:import-from #:koya-server/db/contents
                #:list-contents #:find-contents-by-ids #:content-id #:content-data)
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

(defun reference-options (space field)
  "Every content of FIELD's target model as (id . label), sorted by label, drafts
included: a reference may be set to one before it is published. Every one, so a
selected id is never taken for missing."
  (when (eq (field-type field) :reference)
    (let ((target (find-model space (field-option field :model))))
      (when target
        (sort (mapcar (lambda (content) (cons (content-id content) (content-label content target)))
                      (list-contents space (model-name target) target (make-query :limit nil) :status :all))
              #'string-lessp :key #'cdr)))))

(defun referenced-ids (field contents)
  "The ids FIELD holds across CONTENTS, one or an array each."
  (loop :for content :in contents
        :for data := (content-data content :draft t)
        :for value := (and data (gethash (field-name field) data))
        :nconc (cond ((stringp value) (list value))
                     ((vectorp value) (remove-if-not #'stringp (coerce value 'list))))))

(defun reference-labels (space model contents)
  "Field name -> hash of referenced id -> label, for every reference field of MODEL,
covering the ids CONTENTS hold. An id missing from it no longer resolves."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) table)
      (when (eq (field-type field) :reference)
        (let ((target (find-model space (field-option field :model)))
              (labels (make-hash-table :test 'equal)))
          (when target
            (maphash (lambda (id content) (setf (gethash id labels) (content-label content target)))
                     (find-contents-by-ids space (model-name target) (referenced-ids field contents))))
          (setf (gethash (field-name field) table) labels))))))
