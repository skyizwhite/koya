(defpackage #:koya-server/usecases/contents/delivery
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-name #:model-fields #:field-name #:field-type #:field-option #:field-many-p)
  (:import-from #:koya/core/json #:jobject #:json-null)
  (:import-from #:koya-server/domain/errors
                #:fail #:not-found)
  (:import-from #:koya-server/domain/query
                #:bad-query #:query-fields #:query-include)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-published #:content-draft-key
                #:content-created-at #:content-updated-at
                #:content-published-at #:content-revised-at #:content-data)
  (:import-from #:koya-server/usecases/ports/config #:public-url)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/ports/media #:find-media)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content #:find-object-content #:list-contents)
  (:import-from #:koya-server/usecases/media/delivery #:media->jobject)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:export #:content->jobject
           #:delivered-contents
           #:delivered-content
           #:delivered-object))
(in-package #:koya-server/usecases/contents/delivery)

;;; A content as koya delivers it -- to the delivery API, and to webhooks, which
;;; carry the same shape: its data with the system fields, media expanded and
;;; richtext pointing at this server.

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
        (bad-query "include: ~s is not a reference field" (first path))))))

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
  "Destructively prefix /media/ paths inside richtext fields with the public URL:
the HTML is rendered by other sites, where a relative path would point at them."
  (let ((base (string-right-trim "/" (public-url))))
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


;;; What the delivery API reads. A content is delivered when it is published, or
;;; with its draft when the caller holds its draft key -- the preview link.

(defun draft-key-p (content draft-key)
  (and draft-key (content-draft-key content) (string= draft-key (content-draft-key content))))

(defun delivered (space model content query draft-key)
  (let ((draft (draft-key-p content draft-key)))
    (unless (or draft (content-published content))
      (fail 'not-found "Content does not exist"))
    (content->jobject content model space :draft draft
                      :fields (query-fields query) :include (query-include query))))

(defun delivered-contents (space model query)
  "(values OBJECTS TOTAL): the published contents of the list model MODEL that
QUERY asks for, and how many there are in all."
  (multiple-value-bind (contents total) (list-contents space (model-name model) model query)
    (values (map 'vector (lambda (c) (content->jobject c model space
                                                       :fields (query-fields query)
                                                       :include (query-include query)))
                 contents)
            total)))

(defun delivered-content (space model id query &key draft-key)
  "Content ID of MODEL. Signals NOT-FOUND unless it is delivered."
  (let ((content (or (find-content space (model-name model) id)
                     (fail 'not-found "Content does not exist"))))
    (delivered space model content query draft-key)))

(defun delivered-object (space model query &key draft-key)
  "The one content of the object model MODEL. Signals NOT-FOUND unless it is delivered."
  (let ((content (or (find-object-content space (model-name model))
                     (fail 'not-found "Content does not exist"))))
    (delivered space model content query draft-key)))
