(defpackage #:koya-server/usecases/contents/labels
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields
                #:field-name #:field-type #:field-option)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/ports/contents #:list-contents #:find-contents-by-ids)
  (:import-from #:koya-server/domain/content #:content-id #:content-data #:content-label)
  (:import-from #:koya-server/domain/query #:make-query)
  (:export #:reference-options
           #:reference-labels))
(in-package #:koya-server/usecases/contents/labels)

;;; What a reference field offers, and what the ids it holds are called.

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
