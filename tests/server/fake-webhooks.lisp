(defpackage #:koya-tests/server/fake-webhooks
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/webhooks #:send-webhook)
  (:export #:*webhook-sender*))
(in-package #:koya-tests/server/fake-webhooks)

;;; The webhooks a test sets off go to *WEBHOOK-SENDER* rather than out over
;;; HTTP. An :around method on the port stands in front of infra's own method;
;;; with no sender set, the call goes through to it.

(defvar *webhook-sender* nil
  "NIL, or a function (URL PAYLOAD HEADERS) that answers (values STATUS BODY ERROR)
in the port's place.")

(defmethod send-webhook :around (url payload headers)
  (if *webhook-sender*
      (funcall *webhook-sender* url payload headers)
      (call-next-method)))
