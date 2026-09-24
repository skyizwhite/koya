(defpackage #:koya-server/web/pages/health
  (:use #:cl #:hsx)
  (:import-from #:koya-server/usecases/system #:store-reachable-p)
  (:import-from #:koya-server/web/auth #:public-path)
  (:export #:@get))
(in-package #:koya-server/web/pages/health)

;; asked by whatever watches the server, which has no session
(public-path "/health")

(defun @get (params)
  "Unauthenticated health check: verifies the database answers."
  (declare (ignore params))
  (store-reachable-p)
  (hsx (p "ok")))
