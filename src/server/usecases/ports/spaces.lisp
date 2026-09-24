(defpackage #:koya-server/usecases/ports/spaces
  (:use #:cl)
  (:export #:list-spaces
           #:find-space
           #:insert-space
           #:delete-space
           #:load-schema
           #:save-schema
           #:find-model
           #:space-webhooks
           #:space-webhook-secret
           #:rotate-webhook-secret
           #:set-webhook-secret
           #:list-deploys
           #:count-deploys
           #:+deploys-kept+))
(in-package #:koya-server/usecases/ports/spaces)

;;; Spaces, the schema deployed to each, and the log of deploys. See
;;; ports/store for what a port is.

(declaim (ftype function list-spaces find-space insert-space delete-space
                load-schema save-schema find-model
                space-webhooks space-webhook-secret rotate-webhook-secret set-webhook-secret
                list-deploys count-deploys))

(defparameter +deploys-kept+ 100
  "Deploys kept per space; older ones are dropped as new ones arrive.")
