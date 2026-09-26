(defpackage #:koya-server/usecases/contents/revisions
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-name #:model-fields #:model-field
                #:field-name #:field-type #:field-option #:field-required-p)
  (:import-from #:koya-core/validate
                #:validate-content #:blank-value-p)
  (:import-from #:koya-core/json
                #:json-array-p #:jkeys)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content #:unique-value-taken-p
                #:list-revisions #:count-revisions #:find-revision)
  (:import-from #:koya-server/domain/content #:content-published)
  (:import-from #:koya-server/usecases/ports/media #:find-media)
  (:export #:restore-data
           #:list-revisions
           #:count-revisions
           #:find-revision))
(in-package #:koya-server/usecases/contents/revisions)

;;; What a revision's data becomes when it is brought back into the editor. The
;;; schema and the space may have moved on since it was written, so each field
;;; is checked against them as they are now; what cannot come back is reported
;;; rather than guessed at.

(defun usable-id-p (space field id)
  "True when ID can still be pointed at: a media in the library, or a content of
the target model that is published. A draft is not: a reference to it would
restore something the site cannot show."
  (and (stringp id)
       (if (eq (field-type field) :media)
           (and (find-media space id) t)
           (let ((target (find-content space (field-option field :model) id)))
             (and target (content-published target) t)))))

(defun drop-unusable-ids (space field value)
  "(values VALUE-WITHOUT-THEM COUNT-DROPPED) for a :reference or :media VALUE,
one id or an array of them. A single id that is dropped leaves NIL."
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

(defun restore-data (space model id revision current)
  "The data to put in the editor for content ID when restoring REVISION (a data
object) over CURRENT (what the editor has now). Returns (values DATA NOTES),
NOTES being (:field NAME :note TEXT) for every field that did not come back as
it was: a field that is gone is left out, a value the field no longer accepts
keeps CURRENT's, and ids that can no longer be pointed at are dropped."
  (let ((data (make-hash-table :test 'equal))
        (notes '()))
    (flet ((note (name text) (push (list :field name :note text) notes))
           (keep-current (name)
             (multiple-value-bind (value found) (gethash name current)
               (when found (setf (gethash name data) value)))))
      (dolist (key (jkeys revision))
        (unless (model-field model key)
          (note key "is no longer a field of this model, so it was left out")))
      (dolist (field (model-fields model))
        (let ((name (field-name field)))
          (multiple-value-bind (value found) (gethash name revision)
            (when (and found (member (field-type field) '(:reference :media)) (not (blank-value-p value)))
              (multiple-value-bind (kept dropped) (drop-unusable-ids space field value)
                (when (plusp dropped)
                  (note name (dropped-note field dropped))
                  (setf value kept
                        found (not (blank-value-p kept))))))
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
