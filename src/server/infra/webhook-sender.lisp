(defpackage #:koya-server/infra/webhook-sender
  (:use #:cl)
  (:import-from #:dexador)
  (:import-from #:dexador.error
                #:http-request-failed #:response-status #:response-body)
  (:import-from #:koya-server/usecases/ports/webhooks
                #:send-webhook))
(in-package #:koya-server/infra/webhook-sender)

;;; Webhooks go out over HTTP with dexador, with short timeouts: a receiver that
;;; hangs holds up only the thread its calls run in.

(defun send-webhook (url payload headers)
  (handler-case
      (multiple-value-bind (body status)
          (dexador:post url :headers (cons '("Content-Type" . "application/json") headers) :content payload
                            :connect-timeout 5 :read-timeout 10)
        (values status body nil))
    (http-request-failed (e)
      (values (response-status e) (response-body e) nil))
    (error (e)
      (let ((message (princ-to-string e)))
        (format *error-output* "~&[koya] webhook ~a failed: ~a~%" url message)
        (values nil nil message)))))
