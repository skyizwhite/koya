(defpackage #:koya-server/usecases/delivery
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:field-name #:field-type #:field-option #:field-many-p
                #:field-fields #:field-row-kinds #:row-kind #:custom-field-fields)
  (:import-from #:koya-core/json #:json-null)
  (:import-from #:koya-server/domain/errors #:fail #:not-found)
  (:import-from #:koya-server/domain/query #:bad-query #:query-include)
  (:import-from #:koya-server/domain/content #:content-published #:content-draft-key #:content-data)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/auth #:secure-string=)
  (:import-from #:koya-server/usecases/ports/media #:find-media)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content #:find-object-content #:list-contents)
  (:export #:delivered
           #:delivered-content
           #:delivered-model
           #:delivered-data
           #:deliver
           #:delivered-list
           #:delivered-list-content
           #:delivered-object))
(in-package #:koya-server/usecases/delivery)

(defstruct (delivered (:constructor make-delivered (content model data)))
  content model data)

(defun copy-object (object)
  (let ((out (make-hash-table :test 'equal)))
    (when object (maphash (lambda (k v) (setf (gethash k out) v)) object))
    out))

(defun expand-reference (space target-model-name value include)
  (let* ((target (find-model space target-model-name))
         (content (and target (stringp value) (find-content space target-model-name value))))
    (and content (content-published content)
         (deliver content target space :include include))))

(defun rows-of (value)
  (and (vectorp value) (not (stringp value)) value))

(defun next-fields (space field)
  (case (field-type field)
    (:custom (field-fields field))
    (:repeater (loop :for kind :in (field-row-kinds field) :append (custom-field-fields kind)))
    (:reference (let ((target (find-model space (field-option field :model))))
                  (and target (model-fields target))))))

(defun check-include (space model include)
  (dolist (path include)
    (loop :for (name . more) :on path
          :for fields := (model-fields model) :then (next-fields space field)
          :for field := (find-if (lambda (f)
                                   (and (string= (field-name f) name)
                                        (or (eq (field-type f) :reference)
                                            (and more (member (field-type f) '(:custom :repeater))))))
                                 fields)
          :for reached :from 1
          :unless field
            :do (bad-query "include: ~s is not a reference field" (format nil "~{~a~^.~}" (subseq path 0 reached))))))

(defun embed-references (object fields space include)
  (dolist (field fields)
    (let* ((name (field-name field))
           (nested (loop :for path :in include
                         :when (string= (first path) name) :collect (rest path)))
           (value (gethash name object)))
      (when (and nested value (not (eq value json-null)))
        (let ((nested (remove nil nested)))
          (case (field-type field)
            (:custom
              (when (hash-table-p value)
                (setf (gethash name object) (embed-references (copy-object value) (field-fields field) space nested))))
            (:repeater
              (when (rows-of value)
                (setf (gethash name object)
                      (map 'vector (lambda (row)
                                     (let ((kind (row-kind field row)))
                                       (if kind
                                           (embed-references (copy-object row) (custom-field-fields kind) space nested)
                                           row)))
                           value))))
            (:reference
              (let ((target (field-option field :model)))
                (setf (gethash name object)
                      (if (field-many-p field)
                          (coerce (remove nil (map 'list (lambda (v) (expand-reference space target v nested)) value)) 'vector)
                          (or (expand-reference space target value nested) json-null))))))))))
  object)

(defun expand-media (object fields space)
  (dolist (field fields object)
    (let ((value (gethash (field-name field) object)))
      (case (field-type field)
        (:media
         (when (and value (not (eq value json-null)))
           (let ((media (and (stringp value) (find-media space value))))
             (setf (gethash (field-name field) object) (or media json-null)))))
        (:custom
         (when (hash-table-p value)
           (setf (gethash (field-name field) object)
                 (expand-media (copy-object value) (field-fields field) space))))
        (:repeater
         (when (rows-of value)
           (setf (gethash (field-name field) object)
                 (map 'vector (lambda (row)
                                (let ((kind (row-kind field row)))
                                  (if kind (expand-media (copy-object row) (custom-field-fields kind) space) row)))
                      value))))))))

(defun deliver (content model space &key draft include)
  (let ((data (copy-object (content-data content :draft draft))))
    (when include (embed-references data (model-fields model) space include))
    (expand-media data (model-fields model) space)
    (make-delivered content model data)))

(defun draft-key-p (content draft-key)
  (and draft-key (content-draft-key content) (secure-string= draft-key (content-draft-key content))))

(defun deliver-if-allowed (space model content query draft-key)
  (let ((draft (draft-key-p content draft-key)))
    (unless (or draft (content-published content))
      (fail 'not-found "Content does not exist"))
    (deliver content model space :draft draft :include (query-include query))))

(defun delivered-list (space model query)
  (check-include space model (query-include query))
  (multiple-value-bind (contents total) (list-contents space (model-name model) model query)
    (values (mapcar (lambda (c) (deliver c model space :include (query-include query))) contents)
            total)))

(defun delivered-list-content (space model id query &key draft-key)
  (check-include space model (query-include query))
  (let ((content (or (find-content space (model-name model) id)
                     (fail 'not-found "Content does not exist"))))
    (deliver-if-allowed space model content query draft-key)))

(defun delivered-object (space model query &key draft-key)
  (check-include space model (query-include query))
  (let ((content (or (find-object-content space (model-name model))
                     (fail 'not-found "Content does not exist"))))
    (deliver-if-allowed space model content query draft-key)))
