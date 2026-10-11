(defpackage #:koya-server/usecases/delivery
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:field-name #:field-type #:field-option #:field-many-p
                #:field-fields #:field-row-kinds #:custom-field-fields #:map-data-fields)
  (:import-from #:koya-core/json #:json-null #:json-array-p)
  (:import-from #:koya-server/domain/errors #:fail #:not-found)
  (:import-from #:koya-server/domain/query #:bad-query #:query-include)
  (:import-from #:koya-server/domain/content #:content-id #:value-ids #:content-published #:content-draft-key #:content-data #:slug-value #:only-one)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/auth #:secure-string=)
  (:import-from #:koya-server/usecases/ports/media #:find-media-by-ids)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content #:find-object-content #:list-contents #:find-contents-by-slug
                #:find-contents-by-ids)
  (:export #:delivered
           #:delivered-content
           #:delivered-model
           #:delivered-data
           #:deliver
           #:delivered-list
           #:delivered-list-content
           #:delivered-list-content-by-slug
           #:delivered-object))
(in-package #:koya-server/usecases/delivery)

(defstruct (delivered (:constructor make-delivered (content model data)))
  content model data)

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

(defun include-under (include path)
  (loop :for p :in include
        :when (and (>= (length p) (length path)) (every #'string= path p))
          :collect (nthcdr (length path) p)))

(defun held-ids (value many)
  (if many
      (and (json-array-p value) (value-ids value))
      (and (stringp value) (plusp (length value)) (list value))))

(defstruct (slot (:constructor %make-slot))
  object name many ids)

(defun make-slot (object name many value)
  (%make-slot :object object :name name :many many :ids (held-ids value many)))

(defun fill-slot (slot found)
  (let ((values (remove nil (mapcar (lambda (id) (gethash id found)) (slot-ids slot)))))
    (setf (gethash (slot-name slot) (slot-object slot))
          (if (slot-many slot) (coerce values 'vector) (or (first values) json-null)))))

(defun ids-of (slots)
  (loop :for slot :in slots :append (slot-ids slot)))

(defun fill-media (slots space)
  (let* ((ids (ids-of slots))
         (found (if ids (find-media-by-ids space ids) (make-hash-table :test 'equal))))
    (dolist (slot slots) (fill-slot slot found))))

(defun fill-references (groups space)
  (maphash (lambda (key slots)
             (destructuring-bind (target-name include) key
               (let ((target (find-model space target-name))
                     (ids (ids-of slots))
                     (found (make-hash-table :test 'equal)))
                 (when (and target ids)
                   (let ((contents (loop :for content :being :the :hash-values
                                           :of (find-contents-by-ids space target-name ids)
                                         :when (content-published content) :collect content)))
                     (loop :for content :in contents
                           :for delivered :in (deliver-all contents target space :include include)
                           :do (setf (gethash (content-id content) found) delivered))))
                 (dolist (slot slots) (fill-slot slot found)))))
           groups))

(defun deliver-all (contents model space &key draft include)
  (let ((media '())
        (references (make-hash-table :test 'equal)))
    (flet ((collect (field object outer)
             (let* ((name (field-name field))
                    (value (gethash name object)))
               (when (and value (not (eq value json-null)))
                 (case (field-type field)
                   (:media (push (make-slot object name (field-many-p field) value) media))
                   (:reference
                    (let ((nested (and include (include-under include (if outer (list (field-name outer) name) (list name))))))
                      (when nested
                        (push (make-slot object name (field-many-p field) value)
                              (gethash (list (field-option field :model) (remove nil nested)) references))))))))))
      (let ((data (mapcar (lambda (content)
                            (map-data-fields (model-fields model) (content-data content :draft draft) #'collect))
                          contents)))
        (fill-media media space)
        (fill-references references space)
        (mapcar (lambda (content data) (make-delivered content model data)) contents data)))))

(defun deliver (content model space &key draft include)
  (first (deliver-all (list content) model space :draft draft :include include)))

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
    (values (deliver-all contents model space :include (query-include query))
            total)))

(defun delivered-list-content (space model id query &key draft-key)
  (check-include space model (query-include query))
  (let ((content (or (find-content space (model-name model) id)
                     (fail 'not-found "Content does not exist"))))
    (deliver-if-allowed space model content query draft-key)))

(defun published-slug-p (model content slug)
  (equal (slug-value model (content-published content)) slug))

(defun delivered-list-content-by-slug (space model slug query &key draft-key)
  (check-include space model (query-include query))
  (let ((content (only-one (find-contents-by-slug space (model-name model) slug))))
    (unless (and content (or (draft-key-p content draft-key) (published-slug-p model content slug)))
      (fail 'not-found "Content does not exist"))
    (deliver-if-allowed space model content query draft-key)))

(defun delivered-object (space model query &key draft-key)
  (check-include space model (query-include query))
  (let ((content (or (find-object-content space (model-name model))
                     (fail 'not-found "Content does not exist"))))
    (deliver-if-allowed space model content query draft-key)))
