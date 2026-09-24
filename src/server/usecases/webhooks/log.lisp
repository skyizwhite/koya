(defpackage #:koya-server/usecases/webhooks/log
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/webhooks
                #:list-deliveries #:count-deliveries #:find-delivery #:delivery-labels #:delivery-models
                #:+deliveries-kept+)
  (:export #:list-deliveries
           #:count-deliveries
           #:find-delivery
           #:delivery-labels
           #:delivery-models
           #:+deliveries-kept+))
(in-package #:koya-server/usecases/webhooks/log)

;;; What came back from each webhook call, so the admin UI can show whether the
;;; receiver took it. A log to glance at after a publish, not an audit trail:
;;; only the newest +DELIVERIES-KEPT+ of a space are kept.
