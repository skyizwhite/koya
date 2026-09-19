(defpackage #:koya-server/lib/presenter
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-fields #:field-name #:field-type #:field-option #:field-many-p #:space-model)
  (:import-from #:koya/core/json
                #:jobject #:json-array-p #:json-null)
  (:import-from #:koya/core/markdown
                #:render-markdown)
  (:import-from #:koya-server/db/contents
                #:content-id #:content-status #:content-published #:content-draft #:content-draft-key
                #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
                #:content-data #:find-content)
  (:export #:content->jobject
           #:admin-content->jobject))
(in-package #:koya-server/lib/presenter)

;;; Shapes content rows for the two APIs.

(defun copy-object (object)
  (let ((out (make-hash-table :test 'equal)))
    (when object (maphash (lambda (k v) (setf (gethash k out) v)) object))
    out))

(defun expand-reference (space target-model-name value depth)
  "Replace a referenced id with the published content object, or NIL when missing."
  (let* ((target (space-model space target-model-name))
         (content (and target (stringp value) (find-content (koya/core/schema:space-name space) target-model-name value))))
    (and content (content-published content)
         (content->jobject content target space :depth (1- depth)))))

(defun decorate (object model space depth)
  "Add rendered HTML for richtext fields and expand references in OBJECT (destructively)."
  (dolist (field (model-fields model))
    (multiple-value-bind (value found) (gethash (field-name field) object)
      (when (and found value (not (eq value json-null)))
        (case (field-type field)
          (:richtext
           (when (stringp value)
             (setf (gethash (format nil "~aHtml" (field-name field)) object) (render-markdown value))))
          (:reference
           (when (and space (plusp depth))
             (let ((target (field-option field :model)))
               (setf (gethash (field-name field) object)
                     (if (field-many-p field)
                         (coerce (remove nil (map 'list (lambda (v) (expand-reference space target v depth)) value)) 'vector)
                         (expand-reference space target value depth))))))))))
  object)

(defun select-fields (object fields)
  (if (null fields)
      object
      (let ((out (make-hash-table :test 'equal)))
        (dolist (name fields)
          (multiple-value-bind (v found) (gethash name object)
            (when found (setf (gethash name out) v))))
        out)))

(defun system-fields (content object)
  (setf (gethash "id" object) (content-id content)
        (gethash "createdAt" object) (content-created-at content)
        (gethash "updatedAt" object) (content-updated-at content)
        (gethash "publishedAt" object) (or (content-published-at content) json-null)
        (gethash "revisedAt" object) (or (content-revised-at content) json-null))
  object)

(defun content->jobject (content model space &key draft fields (depth 1))
  "Delivery API shape: the data merged with system fields. DRAFT serves the draft data."
  (let ((object (copy-object (content-data content :draft draft))))
    (system-fields content object)
    (decorate object model space depth)
    (select-fields object fields)))

(defun admin-content->jobject (content model)
  "Admin API shape: status, both data versions and metadata."
  (flet ((data (object) (and object (decorate (copy-object object) model nil 0))))
    (jobject "id" (content-id content)
             "status" (content-status content)
             "published" (or (data (content-published content)) json-null)
             "draft" (or (data (content-draft content)) json-null)
             "draftKey" (or (content-draft-key content) json-null)
             "createdAt" (content-created-at content)
             "updatedAt" (content-updated-at content)
             "publishedAt" (or (content-published-at content) json-null)
             "revisedAt" (or (content-revised-at content) json-null))))
