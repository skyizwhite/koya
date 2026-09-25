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

(defun dependencies (name &optional (prefix "koya-server/"))
  (remove-if-not (lambda (d) (and (stringp d) (eql 0 (search prefix d))))
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

;;; The same rule for what is outside koya: a library that is how a request
;;; arrives, or how a row is stored, belongs to the layer that does that. A use
;;; case that imported one would be back to knowing HTTP or SQL, whatever its
;;; imports from koya-server say.

(defparameter +library-homes+
  '(("dbi" :infra) ("dbd-sqlite3" :infra) ("zippy" :infra) ("dexador" :infra)
    ("clack" :web :main) ("lack" :web :infra) ("ningle" :web) ("jingle" :web)
    ("hsx" :web) ("woo" :main) ("hunchentoot" :main))
  "A library and the layers that may import it. A name covers its subsystems
and extensions: \"lack\" covers lack/request and lack-mw, \"ningle\" covers
ningle-actions. lack is infra's as well: the session store infra keeps in the
database speaks its protocol.")

(defun library-home (dependency)
  (assoc-if (lambda (library)
              (or (string= library dependency)
                  (and (< (length library) (length dependency))
                       (string= library dependency :end2 (length library))
                       (member (char dependency (length library)) '(#\/ #\-)))))
            +library-homes+))

(deftest libraries-stay-in-their-layer
  (dolist (name (server-systems))
    (let ((from (layer name)))
      (dolist (dependency (dependencies name ""))
        (let ((home (library-home dependency)))
          (when home
            (ok (member from (rest home))
                (format nil "~a (~(~a~)) may use ~a" name from dependency))))))))
