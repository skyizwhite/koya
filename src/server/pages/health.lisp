(defpackage #:koya-server/pages/health
  (:use #:cl #:hsx)
  (:import-from #:koya-server/db/connection #:fetch-one)
  (:export #:@get))
(in-package #:koya-server/pages/health)

(defun @get (params)
  "Unauthenticated health check: verifies the database answers."
  (declare (ignore params))
  (fetch-one "SELECT 1 AS ok")
  (hsx (p "ok")))
