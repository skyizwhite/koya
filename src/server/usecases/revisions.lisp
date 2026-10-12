(defpackage #:koya-server/usecases/revisions
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-fields #:field-name #:field-type #:field-option #:field-unique-p
                #:field-required-p #:map-data-fields #:field-value #:without-field #:field-key)
  (:import-from #:koya-core/validate #:validate-content #:blank-value-p)
  (:import-from #:koya-core/data #:array-p)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content #:list-revisions #:count-revisions
                #:find-revision)
  (:import-from #:koya-server/domain/content #:content-published-p)
  (:import-from #:koya-server/usecases/ports/media #:find-media)
  (:import-from #:koya-server/usecases/contents #:value-taken-p)
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
             (and target (content-published-p target))))))

(defun drop-unusable-ids (space field value)
  (if (array-p value)
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

(defun drop-unusable (space model revision)
  (let ((notes (make-hash-table :test 'equal)))
    (values (map-data-fields (model-fields model) revision
                             (lambda (field object outer)
                               (let ((value (field-value object field)))
                                 (if (and (member (field-type field) '(:reference :media)) (not (blank-value-p value)))
                                     (multiple-value-bind (left dropped) (drop-unusable-ids space field value)
                                       (cond ((zerop dropped) object)
                                             (t (push (if outer
                                                          (format nil "~a ~a" (field-name field) (dropped-note field dropped))
                                                          (dropped-note field dropped))
                                                      (gethash (field-name (or outer field)) notes))
                                                (if (blank-value-p left)
                                                    (without-field object field)
                                                    (progn (setf (field-value object field) left) object)))))
                                     object))))
            notes)))

(defun restore-data (space model id revision current)
  (multiple-value-bind (revision dropped) (drop-unusable space model revision)
    (let ((data '())
          (notes '()))
      (flet ((note (name text) (push (list :field name :note text) notes))
             (keep (field value) (setf data (append data (list (field-key field) value)))))
      (flet ((keep-current (field)
               (multiple-value-bind (value found) (field-value current field)
                 (when found (keep field value)))))
        (dolist (field (model-fields model))
          (let* ((name (field-name field))
                 (lost (gethash name dropped)))
            (when lost (note name (format nil "~{~a~^; ~}" (reverse lost))))
            (multiple-value-bind (value found) (field-value revision field)
              (let ((errors (and found (validate-content model (list (field-key field) value) :partial t))))
                (cond ((and (not found) (field-required-p field) (not (eq (field-type field) :boolean)))
                       (note name "is required now and this version has no value, so it keeps the current one")
                       (keep-current field))
                      ((not found))
                      (errors
                       (note name (format nil "keeps the current value: the field no longer accepts this version's (it ~a)"
                                          (getf (first errors) :message)))
                       (keep-current field))
                      ((and (field-unique-p field) (not (blank-value-p value))
                            (value-taken-p space model field value :exclude-id id))
                       (note name "keeps the current value: this version's is taken by another content")
                       (keep-current field))
                      (t (keep field value)))))))))
      (values data (nreverse notes)))))
