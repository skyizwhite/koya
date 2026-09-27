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

(defgeneric send-webhook (url payload headers))

(defgeneric record-delivery (space &key label url model event content-id ok status response error duration-ms))

(defgeneric list-deliveries (space &key label model limit offset))

(defgeneric count-deliveries (space &key label model))

(defgeneric find-delivery (space id))

(defgeneric delivery-labels (space))

(defgeneric delivery-models (space))

(defparameter +deliveries-kept+ 200)
