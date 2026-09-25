(uiop:define-package #:koya-server/infra
  (:nicknames #:koya-server/infra/main)
  (:use #:cl)
  (:import-from #:koya-server/infra/env #:db-path #:server-port)
  (:import-from #:koya-server/infra/db/main #:open-store #:close-store #:write-snapshot)
  ;; loaded for the methods they add to the ports
  (:import-from #:koya-server/infra/media-files)
  (:import-from #:koya-server/infra/webhook-sender)
  (:import-from #:koya-server/infra/archives)
  (:export #:db-path
           #:server-port
           #:open-store
           #:close-store
           #:write-snapshot))
(in-package #:koya-server/infra)

;;; Every port's implementation -- the store, the media files, sending webhooks,
;;; space archives, the environment -- loaded together, and what koya-server/main needs to start
;;; them. Imported by its file name, koya-server/infra/main.
