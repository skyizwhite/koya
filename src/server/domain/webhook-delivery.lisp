(defpackage #:koya-server/domain/webhook-delivery
  (:use #:cl)
  (:export #:delivery #:make-delivery
           #:delivery-id #:delivery-space #:delivery-label #:delivery-url #:delivery-model
           #:delivery-event #:delivery-content-id #:delivery-ok #:delivery-status
           #:delivery-response #:delivery-error #:delivery-duration-ms #:delivery-created-at))
(in-package #:koya-server/domain/webhook-delivery)

;;; One webhook call and what came back: STATUS and RESPONSE when the receiver
;;; answered, ERROR when it could not be reached.

(defstruct delivery
  id space label url model event content-id ok status response error duration-ms created-at)
