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
           #:set-webhook-secret))
(in-package #:koya-server/usecases/ports/spaces)

(defgeneric list-spaces ())

(defgeneric find-space (name))

(defgeneric insert-space (name webhook-secret))

(defgeneric delete-space (name))

(defgeneric load-schema (space-name))

(defgeneric save-schema (space-name schema changes &key by))

(defgeneric find-model (space-name model-name))

(defgeneric space-webhooks (name))

(defgeneric space-webhook-secret (space-name))

(defgeneric set-webhook-secret (space-name secret))
