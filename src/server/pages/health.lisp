(defpackage #:koya-server/pages/health
  (:use #:cl #:hsx)
  (:import-from #:koya-server/usecases/system #:store-reachable-p)
  (:export #:@get))
(in-package #:koya-server/pages/health)

(defun @get (params)
  "Unauthenticated health check: verifies the database answers."
  (declare (ignore params))
  (store-reachable-p)
  (hsx (p "ok")))
