(defpackage #:koya-server/usecases/contents/delivery
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-name #:model-fields #:field-name #:field-type #:field-option #:field-many-p)
  (:import-from #:koya/core/json #:json-null)
  (:import-from #:koya-server/domain/errors
                #:fail #:not-found)
  (:import-from #:koya-server/domain/query
                #:bad-query #:query-include)
  (:import-from #:koya-server/domain/content
                #:content-published #:content-draft-key #:content-data)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/ports/media #:find-media)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content #:find-object-content #:list-contents)
  (:export #:delivered
           #:delivered-content
           #:delivered-model
           #:delivered-data
           #:deliver
           #:delivered-list
           #:delivered-one
           #:delivered-object))
(in-package #:koya-server/usecases/contents/delivery)

;;; A content as koya delivers it, to the delivery API and to webhooks alike:
;;; its data with every media field holding its media, and the references a
;;; query names holding the contents they point at. How that reads on the wire
;;; is the presenter's (web/presenters).

(defstruct (delivered (:constructor make-delivered (content model data)))
  "CONTENT of MODEL as delivered. DATA is a copy of its data in which a media
field holds the media, or JSON null for one no longer in the library, and a
reference that was asked for holds a DELIVERED, or JSON null for one that is
missing or unpublished; one not asked for stays an id."
  content model data)

(defun copy-object (object)
  (let ((out (make-hash-table :test 'equal)))
    (when object (maphash (lambda (k v) (setf (gethash k out) v)) object))
    out))

(defun expand-reference (space target-model-name value include)
  "The content a referenced id names, delivered, or NIL when it is missing or
unpublished. INCLUDE applies to the embedded content's own references."
  (let* ((target (find-model space target-model-name))
         (content (and target (stringp value) (find-content space target-model-name value))))
    (and content (content-published content)
         (deliver content target space :include include))))

(defun check-include (include model)
  "Every top-level INCLUDE name must be a reference field of MODEL."
  (dolist (path include)
    (let ((field (find (first path) (model-fields model) :key #'field-name :test #'string=)))
      (unless (and field (eq (field-type field) :reference))
        (bad-query "include: ~s is not a reference field" (first path))))))

(defun embed-references (object model space include)
  "Destructively replace the ids of the reference fields named in INCLUDE with the
referenced contents. A path a.b embeds a, and b inside each embedded a."
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

(defun expand-media (object model space)
  "Destructively replace :media ids with the media they name; an id that no longer
exists becomes JSON null. Always done: whoever reads a content needs the file."
  (dolist (field (model-fields model) object)
    (when (eq (field-type field) :media)
      (let ((value (gethash (field-name field) object)))
        (when (and value (not (eq value json-null)))
          (let ((media (and (stringp value) (find-media space value))))
            (setf (gethash (field-name field) object) (or media json-null))))))))

(defun deliver (content model space &key draft include)
  "CONTENT of MODEL as delivered (see DELIVERED): its draft data with DRAFT, else
its published data. References stay ids unless named in INCLUDE."
  (let ((data (copy-object (content-data content :draft draft))))
    (when include (embed-references data model space include))
    (expand-media data model space)
    (make-delivered content model data)))

;;; What the delivery API reads. A content is delivered when it is published, or
;;; with its draft when the caller holds its draft key -- the preview link.

(defun draft-key-p (content draft-key)
  (and draft-key (content-draft-key content) (string= draft-key (content-draft-key content))))

(defun deliver-if-allowed (space model content query draft-key)
  (let ((draft (draft-key-p content draft-key)))
    (unless (or draft (content-published content))
      (fail 'not-found "Content does not exist"))
    (deliver content model space :draft draft :include (query-include query))))

(defun delivered-list (space model query)
  "(values DELIVERED TOTAL): the published contents of the list model MODEL that
QUERY asks for, and how many there are in all."
  (multiple-value-bind (contents total) (list-contents space (model-name model) model query)
    (values (mapcar (lambda (c) (deliver c model space :include (query-include query))) contents)
            total)))

(defun delivered-one (space model id query &key draft-key)
  "Content ID of MODEL. Signals NOT-FOUND unless it is delivered."
  (let ((content (or (find-content space (model-name model) id)
                     (fail 'not-found "Content does not exist"))))
    (deliver-if-allowed space model content query draft-key)))

(defun delivered-object (space model query &key draft-key)
  "The one content of the object model MODEL. Signals NOT-FOUND unless it is delivered."
  (let ((content (or (find-object-content space (model-name model))
                     (fail 'not-found "Content does not exist"))))
    (deliver-if-allowed space model content query draft-key)))
