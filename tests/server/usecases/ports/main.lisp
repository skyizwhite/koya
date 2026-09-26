(defpackage #:koya-tests/server/usecases/ports/main
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/ports/main #:+ports+)
  (:import-from #:okite #:unimplemented-generics))
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

;;; A port's function the web needs reaches it through one use case, which
;;; re-exports it (docs/ARCHITECTURE.md). One: a page then has one place to
;;; import it from, and the reader one place to look.

(defun use-case-packages ()
  (remove-if-not (lambda (package)
                   (let ((name (package-name package)))
                     (and (eql 0 (search "KOYA-SERVER/USECASES/" name))
                          (not (string= name "KOYA-SERVER/USECASES/PORTS"))
                          (not (search "/USECASES/PORTS/" name)))))
                 (list-all-packages)))

(deftest a-port-function-has-one-home
  (let ((homes (make-hash-table :test 'eq)))
    (dolist (package (use-case-packages))
      (do-external-symbols (symbol package)
        (when (member (symbol-package symbol) +ports+ :key #'find-package)
          (push (package-name package) (gethash symbol homes)))))
    (ok (plusp (hash-table-count homes)) "use cases re-export port functions")
    (maphash (lambda (symbol packages)
               (ok (null (rest packages))
                   (format nil "~a is re-exported by ~{~a~^ and ~}" symbol (reverse packages))))
             homes)))

(deftest every-port-is-implemented
  (ok (null (unimplemented-generics +ports+)) "infra implements every port"))
