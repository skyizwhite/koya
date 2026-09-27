(defpackage #:koya-spec/server/fake-webhooks
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/webhooks #:send-webhook #:resolve-host)
  (:export #:*webhook-sender* #:*address*))
(in-package #:koya-spec/server/fake-webhooks)

;;; The webhooks a test sets off go to *WEBHOOK-SENDER* rather than out over
;;; HTTP. An :around method on the port stands in front of infra's own method;
;;; with no sender set, the call goes through to it.

(defvar *webhook-sender* nil
  "NIL, or a function (URL PAYLOAD HEADERS) that answers (values STATUS BODY ERROR)
in the port's place.")

(defvar *address* nil
  "While *WEBHOOK-SENDER* runs, the address the call was to connect to.")

(defmethod send-webhook :around (url payload headers address)
  (if *webhook-sender*
      (let ((*address* address))
        (funcall *webhook-sender* url payload headers))
      (call-next-method)))

;;; While a sender stands in, a host name resolves to a public address without
;;; asking DNS; an address written as one resolves to itself.

(defun address-literal-p (host)
  (every (lambda (c) (or (digit-char-p c 16) (member c '(#\. #\:)))) host))

(defmethod resolve-host :around (host)
  (if (and *webhook-sender* (not (address-literal-p host)))
      (list #(93 184 216 34))
      (call-next-method)))
