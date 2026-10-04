(defpackage #:koya-server/usecases/revisions
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:field-name #:field-type #:field-option
                #:field-required-p #:field-fields)
  (:import-from #:koya-core/validate #:validate-content #:blank-value-p)
  (:import-from #:koya-core/json #:json-array-p)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content #:unique-value-taken-p #:list-revisions #:count-revisions
                #:find-revision)
  (:import-from #:koya-server/domain/content #:content-published)
  (:import-from #:koya-server/usecases/ports/media #:find-media)
  (:export #:restore-data
           #:list-revisions
           #:count-revisions
           #:find-revision))
(in-package #:koya-server/usecases/revisions)

(defun usable-id-p (space field id)
  (and (stringp id)
       (if (eq (field-type field) :media)
           (and (find-media space id) t)
           (let ((target (find-content space (field-option field :model) id)))
             (and target (content-published target) t)))))

(defun drop-unusable-ids (space field value)
  (if (json-array-p value)
      (let ((kept (remove-if-not (lambda (id) (usable-id-p space field id)) value)))
        (values kept (- (length value) (length kept))))
      (if (usable-id-p space field value)
          (values value 0)
          (values nil 1))))

(defun dropped-note (field count)
  (if (eq (field-type field) :media)
      (format nil "lost ~a media that ~:*~[are~;is~:;are~] no longer in the library" count)
      (format nil "lost ~a reference~:p to content~:p that ~:*~[were~;was~:;were~] deleted or ~
                   ~:*~[are~;is~:;are~] not published" count)))

(defun drop-unusable-inside (space field value)
  (let ((kept (make-hash-table :test 'equal))
        (notes '()))
    (maphash (lambda (k v) (setf (gethash k kept) v)) value)
    (dolist (inner (field-fields field))
      (let ((v (gethash (field-name inner) kept)))
        (when (and (member (field-type inner) '(:reference :media)) (not (blank-value-p v)))
          (multiple-value-bind (left dropped) (drop-unusable-ids space inner v)
            (when (plusp dropped)
              (push (format nil "~a ~a" (field-name inner) (dropped-note inner dropped)) notes)
              (if (blank-value-p left)
                  (remhash (field-name inner) kept)
                  (setf (gethash (field-name inner) kept) left)))))))
    (values kept (and notes (format nil "~{~a~^; ~}" (nreverse notes))))))

(defun restore-data (space model id revision current)
  (let ((data (make-hash-table :test 'equal))
        (notes '()))
    (flet ((note (name text) (push (list :field name :note text) notes))
           (keep-current (name)
             (multiple-value-bind (value found) (gethash name current)
               (when found (setf (gethash name data) value)))))
      (dolist (field (model-fields model))
        (let ((name (field-name field)))
          (multiple-value-bind (value found) (gethash name revision)
            (when (and found (member (field-type field) '(:reference :media)) (not (blank-value-p value)))
              (multiple-value-bind (kept dropped) (drop-unusable-ids space field value)
                (when (plusp dropped)
                  (note name (dropped-note field dropped))
                  (setf value kept
                        found (not (blank-value-p kept))))))
            (when (and found (eq (field-type field) :custom) (hash-table-p value))
              (multiple-value-bind (kept note) (drop-unusable-inside space field value)
                (when note (note name note))
                (setf value kept)))
            (let ((errors (and found
                               (validate-content model (let ((one (make-hash-table :test 'equal)))
                                                         (setf (gethash name one) value)
                                                         one)
                                                 :partial t))))
              (cond ((and (not found) (field-required-p field) (not (eq (field-type field) :boolean)))
                     (note name "is required now and this version has no value, so it keeps the current one")
                     (keep-current name))
                    ((not found))
                    (errors
                     (note name (format nil "keeps the current value: the field no longer accepts this version's (it ~a)"
                                        (getf (first errors) :message)))
                     (keep-current name))
                    ((and (field-option field :unique) (not (blank-value-p value))
                          (unique-value-taken-p space (model-name model) name value :exclude-id id))
                     (note name "keeps the current value: this version's is taken by another content")
                     (keep-current name))
                    (t (setf (gethash name data) value))))))))
    (values data (nreverse notes))))
