(defpackage #:koya-server/domain/deploy
  (:use #:cl)
  (:export #:deploy #:make-deploy
           #:deploy-id #:deploy-space #:deploy-changes #:deploy-change-count
           #:deploy-destructive #:deploy-by #:deploy-created-at
           #:change #:make-change
           #:change-op #:change-destructive #:change-description))
(in-package #:koya-server/domain/deploy)

;;; A deploy that changed something, as the log keeps it: each change by its
;;; op, whether it could lose content, and the line PLAN printed for it. The
;;; schema document itself is not kept: this says what changed, not what it was.

(defstruct deploy
  id space changes change-count destructive by created-at)

(defstruct change
  op destructive description)
