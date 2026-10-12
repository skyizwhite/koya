(defpackage #:koya-server/domain/id
  (:use #:cl)
  (:import-from #:ironclad
                #:strong-random)
  (:export #:new-id
           #:+id-pattern+))
(in-package #:koya-server/domain/id)

(defparameter +id-pattern+ "[0-9a-z]{12}|[0-9A-Z]{26}")

(defun new-id ()
  (string-downcase (format nil "~36,12,'0R" (strong-random (expt 36 12)))))
