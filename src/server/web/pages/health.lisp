(defpackage #:koya-server/web/pages/health
  (:use #:cl #:hsx)
  (:import-from #:koya-server/usecases/system #:store-reachable-p)
  (:import-from #:koya-server/web/auth #:public-path)
  (:export #:@get))
(in-package #:koya-server/web/pages/health)

(public-path "/health")

(defun @get (params)
  (declare (ignore params))
  (store-reachable-p)
  (hsx (p "ok")))
