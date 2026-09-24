(defpackage #:koya-server/usecases/ports/config
  (:use #:cl)
  (:export #:public-url
           #:owner-secret
           #:dev-mode-p))
(in-package #:koya-server/usecases/ports/config)

;;; What the instance is told when it starts. See ports/store for what a port is.

(declaim (ftype function public-url owner-secret dev-mode-p))

;; (public-url): the URL this server is reached at, as configured. Absolute media
;; URLs are made from it, and a write may come from it as well as from the Host.
;; (owner-secret): the secret the owner logs in with.
;; (dev-mode-p): true in development.
