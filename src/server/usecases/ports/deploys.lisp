(defpackage #:koya-server/usecases/ports/deploys
  (:use #:cl)
  (:export #:list-deploys
           #:count-deploys
           #:+deploys-kept+))
(in-package #:koya-server/usecases/ports/deploys)

(defgeneric list-deploys (space &key limit offset))

(defgeneric count-deploys (space))

(defparameter +deploys-kept+ 100)
