(defpackage #:koya-spec/server/layers
  (:use #:cl #:rove)
  (:import-from #:okite #:define-layers #:layer-violations))
(in-package #:koya-spec/server/layers)

;;; The dependency rule (docs/ARCHITECTURE.md): each layer depends on the ones
;;; inside it and nothing further out. The web reaches ports through the use
;;; cases only, but for the one it implements, ports/presenters; nothing but
;;; main reaches infra.
;;;
;;; Inside the web, the three routers -- the admin UI's pages and the two APIs,
;;; file-routed -- are the outermost: they use the rest of web/ (and the pages
;;; ui/), and nothing uses them, as ningle-fbr loads each file by its path. Each
;;; is isolated, so no route uses another: what two routes share (a URL, a
;;; component) is in web/ or ui/.
;;;
;;; The same rule holds for what is outside koya: a library that is how a
;;; request arrives, or how a row is stored, belongs to the layer that does that.
;;; A use case that imported one would be back to knowing HTTP or SQL, whatever
;;; its imports from koya-server say. lack is infra's as well: the session store
;;; infra keeps in the database speaks its protocol. ningle is reached through
;;; jingle, which re-exports it, so there is one name for the router.
;;;
;;; The server and the SDK share koya-core and nothing else: the SDK is what a
;;; site loads, and changes for the site's sake. koya-core is the vocabulary of
;;; the domain, so every layer may use it.

(define-layers koya-server
  (:layers (:domain          "domain/")
           (:presenter-ports "usecases/ports/presenters")
           (:ports           "usecases/ports/")
           (:usecases        "usecases/")
           (:infra           "infra/")
           (:web             "web/")
           (:ui              "web/ui/")
           (:pages           "web/pages/")
           (:api             "web/api/")
           (:admin-api       "web/admin-api/")
           (:main            "main"))
  (:allow (:ports           :domain :presenter-ports)
          (:presenter-ports :domain)
          (:usecases        :domain :ports :presenter-ports)
          (:infra           :domain :ports)
          (:web             :domain :usecases :presenter-ports)
          (:ui              :domain :usecases :web)
          (:pages           :domain :usecases :web :ui)
          (:api             :domain :usecases :web)
          (:admin-api       :domain :usecases :web)
          (:main            :domain :ports :presenter-ports :usecases :infra :web))
  (:isolated :pages :api :admin-api)
  (:libraries ("cl-dbi" :infra) ("zippy" :infra) ("dexador" :infra) ("usocket" :infra) ("cl-dotenv" :infra)
              ("clack" :main) ("lack" :web :infra) ("lack-mw" :web)
              ("jingle" :web :ui :pages :admin-api)
              ("ningle-actions" :web :ui :pages) ("ningle-fbr" :web) ("smart-buffer" :web)
              ("hsx" :web :ui :pages) ("okite" :main))
  (:anywhere "koya-core" "alexandria" "cl-ppcre" "babel" "ironclad" "local-time"
             "bordeaux-threads" "quri")
  (:forbid "koya-sdk" "ningle"))

(deftest layers
  (let ((violations (layer-violations 'koya-server)))
    (ok (null violations) (format nil "~{~a~^~%~}" violations))))
