(defpackage #:koya-server/domain/id
  (:use #:cl)
  (:import-from #:ironclad
                #:strong-random)
  (:export #:new-id))
(in-package #:koya-server/domain/id)

(defun new-id ()
  (string-downcase (format nil "~36,12,'0R" (strong-random (expt 36 12)))))
