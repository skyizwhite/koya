(defpackage #:koya-tests/server/layers
  (:use #:cl #:rove)
  (:import-from #:okite #:define-layers #:layer-violations))
(in-package #:koya-tests/server/layers)

;;; The dependency rule (docs/ARCHITECTURE.md): each layer depends on the ones
;;; inside it and nothing further out. The web reaches ports through the use
;;; cases only, but for the one it implements, ports/presenters; nothing but
;;; main reaches infra.
;;;
;;; The same rule holds for what is outside koya: a library that is how a
;;; request arrives, or how a row is stored, belongs to the layer that does that.
;;; A use case that imported one would be back to knowing HTTP or SQL, whatever
;;; its imports from koya-server say. lack is infra's as well: the session store
;;; infra keeps in the database speaks its protocol.
;;;
;;; The server and the SDK share koya-core and nothing else: the SDK is what a
;;; site loads, and changes for the site's sake.

(define-layers koya-server
  (:layers (:domain          "domain/")
           (:presenter-ports "usecases/ports/presenters")
           (:ports           "usecases/ports/")
           (:usecases        "usecases/")
           (:infra           "infra/")
           (:web             "web/")
           (:main            "main"))
  (:allow (:ports           :domain :presenter-ports)
          (:presenter-ports :domain)
          (:usecases        :domain :ports :presenter-ports)
          (:infra           :domain :ports)
          (:web             :domain :usecases :presenter-ports)
          (:main            :domain :ports :presenter-ports :usecases :infra :web))
  (:libraries ("dbi" :infra) ("dbd-sqlite3" :infra) ("zippy" :infra) ("dexador" :infra)
              ("clack" :web :main) ("lack" :web :infra) ("ningle" :web) ("jingle" :web)
              ("hsx" :web) ("woo" :main) ("hunchentoot" :main))
  (:forbid "koya-sdk"))

(deftest layers
  (let ((violations (layer-violations 'koya-server)))
    (ok (null violations) (format nil "~{~a~^~%~}" violations))))
