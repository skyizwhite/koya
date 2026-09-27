(defpackage #:koya-server/usecases/ports/presenters
  (:use #:cl)
  (:export #:webhook-payload))
(in-package #:koya-server/usecases/ports/presenters)

(defgeneric webhook-payload (space model id event old new))
