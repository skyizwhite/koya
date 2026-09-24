(defpackage #:koya-server/domain/revision
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-fields #:field-name)
  (:import-from #:koya/core/json
                #:json-equal #:jkeys)
  (:export #:revision #:make-revision
           #:revision-id #:revision-content-id #:revision-event #:revision-data
           #:revision-by #:revision-created-at
           #:changed-keys))
(in-package #:koya-server/domain/revision)

;;; What one write left a content with. EVENT is "draft", "publish", "unpublish"
;;; or "discard"; BY names who wrote it, as usecases/actor's *ACTOR* does.

(defstruct revision
  id content-id event data by created-at)

(defun changed-keys (model before after)
  "The keys whose value differs between BEFORE and AFTER (either may be NIL): the
model's fields in its order, then keys it no longer has."
  (let* ((fields (mapcar #'field-name (model-fields model)))
         (gone (remove-if (lambda (key) (member key fields :test #'string=))
                          (remove-duplicates (append (and before (jkeys before)) (jkeys after))
                                             :test #'string=))))
    (remove-if (lambda (key)
                 (multiple-value-bind (a found-a) (if before (gethash key before) (values nil nil))
                   (multiple-value-bind (b found-b) (gethash key after)
                     (or (and (not found-a) (not found-b))
                         (and found-a found-b (json-equal a b))))))
               (append fields (sort gone #'string<)))))
