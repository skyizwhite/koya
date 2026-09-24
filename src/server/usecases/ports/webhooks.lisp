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

(defgeneric send-webhook (url payload headers)
  (:documentation "POST the string PAYLOAD to URL with the HEADERS alist. Returns (values
STATUS BODY ERROR): a 4xx or 5xx is an answer and carries its status and
body; only a call that got no answer has ERROR."))

(defgeneric record-delivery (space &key label url model event content-id ok status response error duration-ms)
  (:documentation "Store one call's outcome, keeping only the newest +DELIVERIES-KEPT+ of SPACE."))

(defgeneric list-deliveries (space &key label model limit offset)
  (:documentation "Newest first. LABEL keeps one webhook's calls; MODEL keeps the calls a change
to that model set off, from its own webhooks and from the space's alike. Given
together they narrow to one webhook's calls for one model."))

(defgeneric count-deliveries (space &key label model))

(defgeneric find-delivery (space id))

(defgeneric delivery-labels (space)
  (:documentation "The webhook labels this space's log holds. Taken from the log rather than
from the schema, so every option finds something and a hook that has since been
renamed away is still reachable."))

(defgeneric delivery-models (space)
  (:documentation "The models this space's log holds. From the log, for the same reason."))

(defparameter +deliveries-kept+ 200
  "Deliveries kept per space; older ones are dropped as new ones arrive.")
