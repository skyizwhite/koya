(defpackage #:koya-tests/server/main
  (:use #:cl #:rove))
(in-package #:koya-tests/server/main)

(deftest every-port-is-implemented
  (ok (null (koya-server::unimplemented-ports)) "infra implements every port")
  (let ((package (make-package "KOYA-SERVER/USECASES/PORTS/PROBE" :use '(#:cl))))
    (unwind-protect
         (let ((name (intern "UNWRITTEN" package)))
           (export name package)
           (eval `(defgeneric ,name (x)))
           (ok (equal (koya-server::unimplemented-ports) (list name)) "a generic with no method is named")
           (eval `(defmethod ,name (x) x))
           (ok (null (koya-server::unimplemented-ports)) "and is not once it has one"))
      (delete-package package))))
