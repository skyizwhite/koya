(defpackage #:koya-server/domain/references
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:schema-models #:model-name #:model-fields #:field-name #:field-type #:field-option)
  (:import-from #:koya-server/domain/content
                #:content-model #:content-published #:content-draft)
  (:export #:reference-fields
           #:refers-p
           #:media-fields
           #:mentioned-ids))
(in-package #:koya-server/domain/references)

(defun fields-by-model (schema predicate)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (model (and schema (schema-models schema)) table)
      (let ((fields (remove-if-not predicate (model-fields model))))
        (when fields (setf (gethash (model-name model) table) fields))))))

(defun reference-fields (schema target)
  (fields-by-model schema (lambda (f) (and (eq (field-type f) :reference)
                                           (equal (field-option f :model) target)))))

(defun media-fields (schema)
  (fields-by-model schema (lambda (f) (member (field-type f) '(:media :richtext)))))

(defun data-refers-p (fields data id)
  (and data
       (some (lambda (field)
               (let ((value (gethash (field-name field) data)))
                 (typecase value
                   (string (string= value id))
                   (vector (find id value :test #'equal)))))
             fields)))

(defun refers-p (content fields id)
  (let ((fields (gethash (content-model content) fields)))
    (and fields
         (or (data-refers-p fields (content-published content) id)
             (data-refers-p fields (content-draft content) id))
         t)))

(defun data-mentioned-ids (fields data ids)
  (and data
       (remove-if-not
        (lambda (id)
          (some (lambda (field)
                  (let ((value (gethash (field-name field) data)))
                    (and (stringp value)
                         (if (eq (field-type field) :media) (string= value id) (search id value)))))
                fields))
        ids)))

(defun mentioned-ids (content fields ids)
  (let ((fields (gethash (content-model content) fields)))
    (and fields
         (union (data-mentioned-ids fields (content-published content) ids)
                (data-mentioned-ids fields (content-draft content) ids)
                :test #'string=))))
