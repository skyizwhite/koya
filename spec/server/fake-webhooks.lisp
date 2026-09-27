(defpackage #:koya-spec/server/fake-webhooks
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/webhooks #:send-webhook #:resolve-host)
  (:export #:*webhook-sender* #:*address*))
(in-package #:koya-spec/server/fake-webhooks)

(defvar *webhook-sender* nil
)

(defvar *address* nil
)

(defmethod send-webhook :around (url payload headers address)
  (if *webhook-sender*
      (let ((*address* address))
        (funcall *webhook-sender* url payload headers))
      (call-next-method)))

(defvar *hosts* '(("::1" #(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1))))

(defun ipv4-literal-p (host)
  (every (lambda (c) (or (digit-char-p c) (char= c #\.))) host))

(defmethod resolve-host :around (host)
  (cond ((null *webhook-sender*) (call-next-method))
        ((assoc host *hosts* :test #'string=) (rest (assoc host *hosts* :test #'string=)))
        ((ipv4-literal-p host) (call-next-method))
        (t (list #(93 184 216 34)))))
