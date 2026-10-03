(defpackage #:koya-server/usecases/ports/sessions
  (:use #:cl)
  (:export #:make-session-store
           #:delete-sessions
           #:+session-seconds+))
(in-package #:koya-server/usecases/ports/sessions)

(defgeneric make-session-store ())

(defgeneric delete-sessions (&key except))

(defparameter +session-seconds+ (* 24 3600))
