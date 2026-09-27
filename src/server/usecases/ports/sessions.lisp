(defpackage #:koya-server/usecases/ports/sessions
  (:use #:cl)
  (:export #:make-session-store
           #:+session-seconds+))
(in-package #:koya-server/usecases/ports/sessions)

(defgeneric make-session-store ())

(defparameter +session-seconds+ (* 24 3600))
