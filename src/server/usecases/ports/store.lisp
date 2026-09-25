(defpackage #:koya-server/usecases/ports/store
  (:use #:cl)
  (:export #:call-with-transaction
           #:with-transaction
           #:store-reachable-p))
(in-package #:koya-server/usecases/ports/store)

;;; A port is a set of generic functions a use case calls and infra implements
;;; (the web, for ports/presenters): the use case depends on the port's package
;;; alone, and the implementation adds the one method each generic has. What a function promises is its documentation
;;; here; how it keeps that promise is infra's. koya-server/main loads infra, and
;;; refuses to load while a generic has no method.

(defgeneric call-with-transaction (thunk)
  (:documentation "Call THUNK so that its writes all happen or none do. The store is held for
THUNK's extent, so a check and the write after it cannot interleave with
another request's."))

(defgeneric store-reachable-p ()
  (:documentation "True when the store answers."))

(defmacro with-transaction (&body body)
  `(call-with-transaction (lambda () ,@body)))
