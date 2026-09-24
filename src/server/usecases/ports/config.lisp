(defpackage #:koya-server/usecases/ports/config
  (:use #:cl)
  (:export #:public-url
           #:owner-secret
           #:dev-mode-p))
(in-package #:koya-server/usecases/ports/config)

;;; What the instance is told when it starts.

(defgeneric public-url ()
  (:documentation "The URL this server is reached at. Absolute media URLs are made from it,
and a write may come from it as well as from the Host."))

(defgeneric owner-secret ()
  (:documentation "The secret the owner logs in with."))

(defgeneric dev-mode-p ()
  (:documentation "True in development."))

