(defpackage #:koya-server/usecases/system
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/store
                #:store-reachable-p)
  (:import-from #:koya-server/usecases/ports/config
                #:public-url #:dev-mode-p)
  (:export #:store-reachable-p
           #:public-url
           #:dev-mode-p))
(in-package #:koya-server/usecases/system)

;;; The instance itself: whether its store answers, and what it was told when it
;;; started.
