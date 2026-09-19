(defpackage #:koya-server/api/not-found
  (:use #:cl)
  (:import-from #:koya-server/lib/http #:error-object)
  (:export #:@not-found))
(in-package #:koya-server/api/not-found)

(defun @not-found ()
  (error-object "not_found" "No such endpoint"))
