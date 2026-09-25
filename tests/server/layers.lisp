(defpackage #:koya-tests/server/layers
  (:use #:cl #:rove))
(in-package #:koya-tests/server/layers)

;;; The dependency rule (docs/ARCHITECTURE.md): each layer depends on the ones
;;; inside it and nothing further out. A file of koya-server is a system of its
;;; own, and what it depends on is what its defpackage imports from, so the rule
;;; is read off ASDF.

(defun layer (name)
  "The layer of the koya-server system NAME."
  (flet ((under (prefix) (eql 0 (search prefix name))))
    (cond ((under "koya-server/domain/") :domain)
          ((string= name "koya-server/usecases/ports/presenters") :presenter-ports)
          ((under "koya-server/usecases/ports/") :ports)
          ((under "koya-server/usecases/") :usecases)
          ((under "koya-server/infra/") :infra)
          ((under "koya-server/web/") :web)
          ((string= name "koya-server/main") :main))))

(defparameter +allowed+
  '((:domain :domain)
    (:ports :domain :ports :presenter-ports)
    (:presenter-ports :domain)
    (:usecases :domain :ports :presenter-ports :usecases)
    (:infra :domain :ports :infra)
    (:web :domain :usecases :presenter-ports :web)
    (:main :domain :ports :presenter-ports :usecases :infra :web))
  "What each layer may depend on. The web reaches ports through the use cases
only, but for the one it implements, ports/presenters; nothing but main reaches
infra.")

(defun server-systems ()
  (let ((root (asdf:system-relative-pathname "koya-server" "src/server/")))
    (mapcar (lambda (file)
              (let ((relative (enough-namestring file root)))
                (format nil "koya-server/~a" (subseq relative 0 (- (length relative) 5)))))
            (directory (merge-pathnames "**/*.lisp" root)))))

(defun dependencies (name)
  (remove-if-not (lambda (d) (and (stringp d) (eql 0 (search "koya-server/" d))))
                 (asdf:system-depends-on (asdf:find-system name))))

(deftest dependency-rule
  (let ((systems (server-systems)))
    (ok (> (length systems) 50) "every file of the server is found")
    (dolist (name systems)
      (let ((from (layer name)))
        (ok from (format nil "~a is in a layer" name))
        (dolist (dependency (dependencies name))
          (let ((to (layer dependency)))
            (ok (member to (rest (assoc from +allowed+)))
                (format nil "~a (~(~a~)) may use ~a (~(~a~))" name from dependency to))))))))
