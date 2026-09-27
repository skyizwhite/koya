(defpackage #:koya-server/usecases/ports/store
  (:use #:cl)
  (:export #:call-with-transaction
           #:with-transaction
           #:store-reachable-p))
(in-package #:koya-server/usecases/ports/store)

(defgeneric call-with-transaction (thunk))

(defgeneric store-reachable-p ())

(defmacro with-transaction (&body body)
  `(call-with-transaction (lambda () ,@body)))
