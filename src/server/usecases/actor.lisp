(defpackage #:koya-server/usecases/actor
  (:use #:cl)
  (:export #:*actor*
           #:+owner+
           #:key-actor
           #:actor-key-label))
(in-package #:koya-server/usecases/actor)

(defvar *actor* "")

(defparameter +owner+ "owner")

(defun key-actor (label)
  (format nil "key:~a" label))

(defun actor-key-label (actor)
  (if (and (>= (length actor) 4) (string= "key:" actor :end2 4))
      (values (subseq actor 4) t)
      nil))
