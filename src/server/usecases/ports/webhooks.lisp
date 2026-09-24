(defpackage #:koya-server/usecases/ports/webhooks
  (:use #:cl)
  (:export #:send-webhook
           #:record-delivery
           #:list-deliveries
           #:count-deliveries
           #:find-delivery
           #:delivery-labels
           #:delivery-models
           #:+deliveries-kept+))
(in-package #:koya-server/usecases/ports/webhooks)

;;; Sending a webhook, and the log of what came back (domain/webhook-delivery).
;;; See ports/store for what a port is.

(declaim (ftype function send-webhook record-delivery list-deliveries count-deliveries
                find-delivery delivery-labels delivery-models))

;; (send-webhook url payload headers): POST the string PAYLOAD to URL with the
;; HEADERS alist. Returns (values STATUS BODY ERROR): a 4xx or 5xx is an answer
;; and carries its status and body; only a call that got no answer has ERROR.

(defparameter +deliveries-kept+ 200
  "Deliveries kept per space; older ones are dropped as new ones arrive.")
