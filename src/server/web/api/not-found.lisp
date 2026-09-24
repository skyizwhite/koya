(defpackage #:koya-server/web/api/not-found
  (:use #:cl)
  (:import-from #:koya-server/web/http #:error-object)
  (:export #:@not-found))
(in-package #:koya-server/web/api/not-found)

(defun @not-found ()
  (error-object "not_found" "No such endpoint"))
