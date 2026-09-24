(defpackage #:koya-server/features/contents/presenter
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-fields #:field-name #:field-type #:field-option #:field-many-p)
  (:import-from #:koya/core/json #:jobject #:json-null)
  (:import-from #:koya-server/lib/query
                #:query-error)
  (:import-from #:koya-server/db/schema-store
                #:find-model)
  (:import-from #:koya-server/db/media
                #:find-media)
  (:import-from #:koya-server/features/media/store
                #:media->jobject)
  (:import-from #:koya-server/lib/env
                #:base-url)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:import-from #:koya-server/db/contents
                #:content-id #:content-status #:content-published #:content-draft #:content-draft-key
                #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at
                #:content-data #:find-content)
  (:export #:content->jobject
           #:admin-content->jobject))
(in-package #:koya-server/features/contents/presenter)

;;; Shapes content rows for the two APIs.

(defun copy-object (object)
  (let ((out (make-hash-table :test 'equal)))
    (when object (maphash (lambda (k v) (setf (gethash k out) v)) object))
    out))

(defun expand-reference (space target-model-name value include)
  "The published content object for a referenced id, or NIL when it is missing or
unpublished. INCLUDE applies to the embedded object's own references."
  (let* ((target (find-model space target-model-name))
         (content (and target (stringp value) (find-content space target-model-name value))))
    (and content (content-published content)
         (content->jobject content target space :include include))))

(defun check-include (include model)
  "Every top-level INCLUDE name must be a reference field of MODEL."
  (dolist (path include)
    (let ((field (find (first path) (model-fields model) :key #'field-name :test #'string=)))
      (unless (and field (eq (field-type field) :reference))
        (error 'query-error :message (format nil "include: ~s is not a reference field" (first path)))))))

(defun embed-references (object model space include)
  "Destructively replace the ids of the reference fields named in INCLUDE with the
referenced objects. A path a.b embeds a, and b inside each embedded a."
  (check-include include model)
  (dolist (field (model-fields model))
    (let* ((name (field-name field))
           (nested (loop :for path :in include
                         :when (string= (first path) name) :collect (rest path)))
           (value (gethash name object)))
      (when (and nested value (not (eq value json-null)))
        (let ((target (field-option field :model))
              (nested (remove nil nested)))
          (setf (gethash name object)
                (if (field-many-p field)
                    (coerce (remove nil (map 'list (lambda (v) (expand-reference space target v nested)) value)) 'vector)
                    (or (expand-reference space target value nested) json-null)))))))
  object)

(defun absolutize-richtext (object model)
  "Destructively prefix /media/ paths inside richtext fields with KOYA_BASE_URL:
the HTML is rendered by other sites, where a relative path would point at them."
  (let ((base (string-right-trim "/" (base-url))))
    (dolist (field (model-fields model) object)
      (when (eq (field-type field) :richtext)
        (let ((value (gethash (field-name field) object)))
          (when (stringp value)
            (setf (gethash (field-name field) object)
                  (regex-replace-all "(src|href)=\"/media/" value (format nil "\\1=\"~a/media/" base)))))))))

(defun expand-media (object model space)
  "Destructively replace :media ids with {id, url, width, height, alt, ...}; an id
that no longer exists becomes null. Always applied: the object is small and
consumers need the URL."
  (dolist (field (model-fields model) object)
    (when (eq (field-type field) :media)
      (let ((value (gethash (field-name field) object)))
        (when (and value (not (eq value json-null)))
          (let ((media (and (stringp value) (find-media space value))))
            (setf (gethash (field-name field) object) (if media (media->jobject media) json-null))))))))

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

(defun content->jobject (content model space &key draft fields include)
  "Delivery API shape: the data merged with system fields. DRAFT serves the draft data.
References stay ids unless named in INCLUDE (see EMBED-REFERENCES)."
  (let ((object (copy-object (content-data content :draft draft))))
    (system-fields content object)
    (when include (embed-references object model space include))
    (expand-media object model space)
    (absolutize-richtext object model)
    (select-fields object fields)))

(defun admin-content->jobject (content model)
  "Admin API shape: status, both data versions and metadata."
  (declare (ignore model))
  (flet ((data (object) (and object (copy-object object))))
    (jobject "id" (content-id content)
             "status" (content-status content)
             "published" (or (data (content-published content)) json-null)
             "draft" (or (data (content-draft content)) json-null)
             "draftKey" (or (content-draft-key content) json-null)
             "createdAt" (content-created-at content)
             "updatedAt" (content-updated-at content)
             "publishedAt" (or (content-published-at content) json-null)
             "revisedAt" (or (content-revised-at content) json-null))))
