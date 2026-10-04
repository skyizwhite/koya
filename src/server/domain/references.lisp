(defpackage #:koya-server/domain/references
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:schema-models #:schema-model #:model-name #:model-fields #:field-name #:field-type #:field-option
                #:field-fields #:field-row-kinds #:custom-field-name #:custom-field-fields)
  (:import-from #:koya-server/domain/content
                #:content-model #:content-published #:content-draft #:content-id #:content-label)
  (:export #:reference-fields
           #:referrers
           #:refers-p
           #:media-fields
           #:mentioned-ids))
(in-package #:koya-server/domain/references)

(defun matching (fields predicate)
  (loop :for field :in fields
        :for inner := (case (field-type field)
                        (:custom (matching (field-fields field) predicate))
                        (:repeater (loop :for kind :in (field-row-kinds field)
                                         :for entries := (matching (custom-field-fields kind) predicate)
                                         :when entries :collect (cons (custom-field-name kind) entries))))
        :when (or inner (funcall predicate field))
          :collect (cons field inner)))

(defun some-inside (test field inner value)
  (if (eq (field-type field) :repeater)
      (and (vectorp value) (not (stringp value))
           (some (lambda (row)
                   (and (hash-table-p row)
                        (let ((entries (cdr (assoc (gethash "fieldId" row) inner :test #'equal))))
                          (and entries (funcall test entries row)))))
                 value))
      (funcall test inner value)))

(defun fields-by-model (schema predicate)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (model (and schema (schema-models schema)) table)
      (let ((fields (matching (model-fields model) predicate)))
        (when fields (setf (gethash (model-name model) table) fields))))))

(defun reference-fields (schema target)
  (fields-by-model schema (lambda (f) (and (eq (field-type f) :reference)
                                           (equal (field-option f :model) target)))))

(defun media-fields (schema)
  (fields-by-model schema (lambda (f) (member (field-type f) '(:media :richtext)))))

(defun data-refers-p (fields data id)
  (and (hash-table-p data)
       (some (lambda (entry)
               (destructuring-bind (field . inner) entry
                 (let ((value (gethash (field-name field) data)))
                   (if inner
                       (some-inside (lambda (entries v) (data-refers-p entries v id)) field inner value)
                       (typecase value
                         (string (string= value id))
                         (vector (find id value :test #'equal)))))))
             fields)))

(defun refers-p (content fields id)
  (let ((fields (gethash (content-model content) fields)))
    (and fields
         (or (data-refers-p fields (content-published content) id)
             (data-refers-p fields (content-draft content) id))
         t)))

(defun mentions-p (fields data id)
  (and (hash-table-p data)
       (some (lambda (entry)
               (destructuring-bind (field . inner) entry
                 (let ((value (gethash (field-name field) data)))
                   (if inner
                       (some-inside (lambda (entries v) (mentions-p entries v id)) field inner value)
                       (typecase value
                         (string (if (eq (field-type field) :media) (string= value id) (search id value)))
                         (vector (and (eq (field-type field) :media) (find id value :test #'equal) t)))))))
             fields)))

(defun data-mentioned-ids (fields data ids)
  (and data (remove-if-not (lambda (id) (mentions-p fields data id)) ids)))

(defun mentioned-ids (content fields ids)
  (let ((fields (gethash (content-model content) fields)))
    (and fields
         (union (data-mentioned-ids fields (content-published content) ids)
                (data-mentioned-ids fields (content-draft content) ids)
                :test #'string=))))

(defun referrers (schema contents)
  (sort (mapcar (lambda (content)
                  (let ((model (schema-model schema (content-model content))))
                    (list :model model :id (content-id content) :label (content-label content model))))
                contents)
        (lambda (a b)
          (let ((ma (model-name (getf a :model))) (mb (model-name (getf b :model))))
            (or (string< ma mb)
                (and (string= ma mb) (string-lessp (getf a :label) (getf b :label))))))))
