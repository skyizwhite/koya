(defpackage #:koya-server/domain/deploy
  (:use #:cl)
  (:export #:deploy #:make-deploy
           #:deploy-id #:deploy-space #:deploy-changes #:deploy-change-count
           #:deploy-destructive #:deploy-by #:deploy-created-at
           #:change #:make-change
           #:change-op #:change-destructive #:change-description))
(in-package #:koya-server/domain/deploy)

(defstruct deploy
  id space changes change-count destructive by created-at)

(defstruct change
  op destructive description)
