(uiop:define-package #:koya-server/usecases/ports
  (:nicknames #:koya-server/usecases/ports/main)
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/store)
  (:import-from #:koya-server/usecases/ports/spaces)
  (:import-from #:koya-server/usecases/ports/deploys)
  (:import-from #:koya-server/usecases/ports/contents)
  (:import-from #:koya-server/usecases/ports/media)
  (:import-from #:koya-server/usecases/ports/keys)
  (:import-from #:koya-server/usecases/ports/webhooks)
  (:import-from #:koya-server/usecases/ports/settings)
  (:import-from #:koya-server/usecases/ports/sessions)
  (:import-from #:koya-server/usecases/ports/config)
  (:import-from #:koya-server/usecases/ports/archives)
  (:import-from #:koya-server/usecases/ports/presenters)
  (:export #:+ports+
           #:unimplemented-ports))
(in-package #:koya-server/usecases/ports)

;;; Every port, for whoever loads an implementation of them to check that it is
;;; whole. Imported by its file name, koya-server/usecases/ports/main.

(defparameter +ports+
  '(#:koya-server/usecases/ports/store
    #:koya-server/usecases/ports/spaces
    #:koya-server/usecases/ports/deploys
    #:koya-server/usecases/ports/contents
    #:koya-server/usecases/ports/media
    #:koya-server/usecases/ports/keys
    #:koya-server/usecases/ports/webhooks
    #:koya-server/usecases/ports/settings
    #:koya-server/usecases/ports/sessions
    #:koya-server/usecases/ports/config
    #:koya-server/usecases/ports/archives
    #:koya-server/usecases/ports/presenters)
  "The packages of the ports. A new port is imported above and named here.")

(defun unimplemented-ports (&optional (ports +ports+))
  "The generic functions of PORTS, package designators, that no method implements."
  (let ((missing '()))
    (dolist (port ports (sort missing #'string< :key #'symbol-name))
      (do-external-symbols (symbol (find-package port))
        (when (and (fboundp symbol)
                   (typep (fdefinition symbol) 'generic-function)
                   (null (sb-mop:generic-function-methods (fdefinition symbol))))
          (push symbol missing))))))
