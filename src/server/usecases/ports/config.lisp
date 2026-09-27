(defpackage #:koya-server/usecases/ports/config
  (:use #:cl)
  (:export #:public-url
           #:owner-secret
           #:dev-mode-p))
(in-package #:koya-server/usecases/ports/config)

(defgeneric public-url ())

(defgeneric owner-secret ())

(defgeneric dev-mode-p ())
