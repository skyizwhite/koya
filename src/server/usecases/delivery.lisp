(defpackage #:koya-server/usecases/delivery
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:field-name #:field-type #:field-option #:field-many-p
                #:field-fields #:field-row-kinds #:custom-field-fields #:map-data-fields #:field-value)
  (:import-from #:koya-server/domain/errors #:fail #:not-found)
  (:import-from #:koya-server/domain/query #:bad-query #:query-include)
  (:import-from #:koya-server/domain/content #:content-id #:held-ids #:content-published #:content-published-p
                #:content-draft-key #:content-data #:slug-value #:only-one)
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

(defun reference-group (field outer include)
  (let ((nested (and include (include-under include (if outer
                                                        (list (field-name outer) (field-name field))
                                                        (list (field-name field)))))))
    (and nested (list (field-option field :model) (remove nil nested)))))

(defun slot-kind (field outer include)
  (case (field-type field)
    (:media :media)
    (:reference (reference-group field outer include))))

(defun filled (value many found)
  (let ((values (remove nil (mapcar (lambda (id) (gethash id found)) (held-ids value many)))))
    (if many (coerce values 'vector) (or (first values) :null))))

(defun delivered-references (space group ids)
  (destructuring-bind (target-name include) group
    (let ((target (find-model space target-name))
          (found (make-hash-table :test 'equal)))
      (let ((contents (loop :for content :being :the :hash-values
                              :of (find-contents-by-ids space target-name ids)
                            :when (content-published-p content) :collect content)))
        (loop :for content :in contents
              :for delivered :in (deliver-all contents target space :include include)
              :do (setf (gethash (content-id content) found) delivered)))
      found)))

(defun deliver-all (contents model space &key draft include)
  (let ((datas (mapcar (lambda (content) (content-data content :draft draft)) contents))
        (media-ids '())
        (groups (make-hash-table :test 'equal)))
    (dolist (data datas)
      (map-data-fields (model-fields model) data
                       (lambda (field object outer)
                         (let ((kind (slot-kind field outer include))
                               (ids (held-ids (field-value object field) (field-many-p field))))
                           (cond ((eq kind :media) (setf media-ids (append ids media-ids)))
                                 (kind (setf (gethash kind groups) (append ids (gethash kind groups))))))
                         object)))
    (let ((media (if media-ids (find-media-by-ids space media-ids) (make-hash-table :test 'equal)))
          (found (make-hash-table :test 'equal)))
      (maphash (lambda (group ids)
                 (setf (gethash group found) (if ids (delivered-references space group ids) (make-hash-table :test 'equal))))
               groups)
      (mapcar (lambda (content data)
                (make-delivered
                 content model
                 (map-data-fields (model-fields model) data
                                  (lambda (field object outer)
                                    (let ((kind (slot-kind field outer include)))
                                      (multiple-value-bind (value present) (field-value object field)
                                        (when (and kind present value (not (eq value :null)))
                                          (setf (field-value object field)
                                                (filled value (field-many-p field)
                                                        (if (eq kind :media) media (gethash kind found)))))))
                                    object))))
              contents datas))))

(defun deliver (content model space &key draft include)
  (first (deliver-all (list content) model space :draft draft :include include)))

(defun draft-key-p (content draft-key)
  (and draft-key (content-draft-key content) (secure-string= draft-key (content-draft-key content))))

(defun deliver-if-allowed (space model content query draft-key)
  (let ((draft (draft-key-p content draft-key)))
    (unless (or draft (content-published-p content))
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
