(defpackage #:koya-server/usecases/actor
  (:use #:cl)
  (:export #:*actor*
           #:+owner+
           #:key-actor
           #:actor-key-label))
(in-package #:koya-server/usecases/actor)

;;; Who a change is made by, as a content's history and the deploy log store it.
;;; The form is decided here, where it is read back; a page words it.

(defvar *actor* ""
  "Who is making the change being made, as it is stored: +OWNER+, or KEY-ACTOR
of a management key's label. The entry point that knows binds it; a change made
from the REPL names nobody, as \"\".")

(defparameter +owner+ "owner")

(defun key-actor (label)
  "The actor a management key labelled LABEL acts as."
  (format nil "key:~a" label))

(defun actor-key-label (actor)
  "(values LABEL T) when ACTOR is a management key's, else NIL."
  (if (and (>= (length actor) 4) (string= "key:" actor :end2 4))
      (values (subseq actor 4) t)
      nil))
