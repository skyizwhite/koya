(defpackage #:koya-server/usecases/ports/deploys
  (:use #:cl)
  (:export #:list-deploys
           #:count-deploys
           #:+deploys-kept+))
(in-package #:koya-server/usecases/ports/deploys)

;;; The log of what each deploy changed (domain/deploy), written by SAVE-SCHEMA
;;; (ports/spaces) and read here.

(defgeneric list-deploys (space &key limit offset)
  (:documentation "Newest first, to the millisecond a ULID carries; LIMIT defaults to 25."))

(defgeneric count-deploys (space))

(defparameter +deploys-kept+ 100
  "Deploys kept per space; older ones are dropped as new ones arrive.")
