(defpackage #:koya-server/domain/revision
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-fields #:field-name)
  (:import-from #:koya-core/json
                #:json-equal)
  (:export #:revision #:make-revision
           #:revision-id #:revision-content-id #:revision-event #:revision-data
           #:revision-by #:revision-created-at
           #:changed-keys))
(in-package #:koya-server/domain/revision)

(defstruct revision
  id content-id event data by created-at)

(defun changed-keys (model before after)
  (let ((fields (mapcar #'field-name (model-fields model))))
    (remove-if (lambda (key)
                 (multiple-value-bind (a found-a) (if before (gethash key before) (values nil nil))
                   (multiple-value-bind (b found-b) (gethash key after)
                     (or (and (not found-a) (not found-b))
                         (and found-a found-b (json-equal a b))))))
               fields)))
