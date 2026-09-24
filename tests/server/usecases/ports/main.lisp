(defpackage #:koya-tests/server/usecases/ports/main
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/ports/main #:+ports+ #:unimplemented-ports))
(in-package #:koya-tests/server/usecases/ports/main)

(deftest every-port-is-listed
  (flet ((names (list) (sort (mapcar #'string-downcase list) #'string<)))
    (ok (equal (names +ports+)
               (names (loop :for file :in (directory (merge-pathnames
                                                      "*.lisp" (asdf:system-relative-pathname
                                                                "koya-server" "src/server/usecases/ports/")))
                            :unless (string= (pathname-name file) "main")
                              :collect (format nil "koya-server/usecases/ports/~a" (pathname-name file)))))
        "+PORTS+ names every file of usecases/ports/")))

(deftest every-port-is-implemented
  (ok (null (unimplemented-ports)) "infra implements every port")
  (let ((probe (make-package "KOYA-TESTS/PORT-PROBE" :use '(#:cl))))
    (unwind-protect
         (let ((name (intern "UNWRITTEN" probe)))
           (export name probe)
           (eval `(defgeneric ,name (x)))
           (ok (equal (unimplemented-ports (list probe)) (list name)) "a generic with no method is named")
           (eval `(defmethod ,name (x) x))
           (ok (null (unimplemented-ports (list probe))) "and is not once it has one"))
      (delete-package probe))))
