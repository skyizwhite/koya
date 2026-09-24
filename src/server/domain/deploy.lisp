(defpackage #:koya-server/domain/deploy
  (:use #:cl)
  (:import-from #:koya/core/json
                #:jget)
  (:export #:deploy #:make-deploy
           #:deploy-id #:deploy-space #:deploy-changes #:deploy-change-count
           #:deploy-destructive #:deploy-by #:deploy-created-at
           #:change-op #:change-destructive #:change-description))
(in-package #:koya-server/domain/deploy)

;;; A deploy that changed something: its CHANGES in the wire format (core/diff's
;;; CHANGE->JOBJECT). The schema document itself is not kept: this says what
;;; changed, not what it was.

(defstruct deploy
  id space changes change-count destructive by created-at)

(defun change-op (change) (jget change "op"))
(defun change-destructive (change) (and (jget change "destructive") t))
(defun change-description (change) (jget change "description"))
