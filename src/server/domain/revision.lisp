(defpackage #:koya-server/domain/revision
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-fields #:field-name #:field-value)
  (:import-from #:koya-core/data
                #:data-equal)
  (:export #:revision #:make-revision
           #:revision-id #:revision-content-id #:revision-event #:revision-data
           #:revision-by #:revision-created-at
           #:changed-keys))
(in-package #:koya-server/domain/revision)

(defstruct revision
  id content-id event data by created-at)

(defun changed-keys (model before after)
  (mapcar #'field-name
          (remove-if (lambda (field)
                       (multiple-value-bind (a found-a) (field-value before field)
                         (multiple-value-bind (b found-b) (field-value after field)
                           (or (and (not found-a) (not found-b))
                               (and found-a found-b (data-equal a b))))))
                     (model-fields model))))
