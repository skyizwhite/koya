(defpackage #:koya-server/usecases/ports/store
  (:use #:cl)
  (:export #:call-with-transaction
           #:with-transaction
           #:store-reachable-p))
(in-package #:koya-server/usecases/ports/store)

;;; A port is a set of functions a use case calls and infra defines: the use case
;;; depends on this package alone, and whichever infra module defines the
;;; functions is loaded by koya-server/main. The FTYPE declamations are the
;;; declarations; the definitions, and their docstrings, are in infra.

(declaim (ftype function call-with-transaction store-reachable-p))

;; (call-with-transaction thunk): THUNK's writes all happen or none do. It also
;; holds the store for THUNK's extent, so a check and the write after it cannot
;; interleave with another request's.

;; (store-reachable-p): true when the store answers.

(defmacro with-transaction (&body body)
  `(call-with-transaction (lambda () ,@body)))
