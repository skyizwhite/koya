(defpackage #:koya-server/usecases/ports/presenters
  (:use #:cl)
  (:export #:webhook-payload))
(in-package #:koya-server/usecases/ports/presenters)

;;; How what a use case sends outward reads there. Unlike the other ports, this
;;; one is the web's to implement (web/presenters): the wire format is decided
;;; where the APIs are, so a webhook and the delivery API carry one shape.

(defgeneric webhook-payload (space model id event old new)
  (:documentation "The body of the webhook sent for EVENT (:publish, :unpublish, :delete or
:draft) on content ID of the model named MODEL in SPACE, as a string. OLD and NEW
are the content before and after, delivered (usecases/contents/delivery), or NIL."))
