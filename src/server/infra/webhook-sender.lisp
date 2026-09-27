(defpackage #:koya-server/infra/webhook-sender
  (:use #:cl)
  (:import-from #:dexador)
  (:import-from #:usocket #:get-hosts-by-name)
  (:import-from #:quri #:uri #:make-uri #:uri-scheme #:uri-host #:uri-port #:uri-path #:uri-query)
  (:import-from #:koya-server/domain/address #:address-string)
  (:import-from #:dexador.error
                #:http-request-failed #:response-status #:response-body)
  (:import-from #:koya-server/usecases/ports/webhooks
                #:send-webhook #:resolve-host))
(in-package #:koya-server/infra/webhook-sender)

(defun host-header (uri)
  (let ((port (uri-port uri)))
    (format nil "~a~@[:~a~]" (uri-host uri) (and port (/= port 80) port))))

(defun connection-target (url address headers)
  (let ((uri (uri url)))
    (if (and address (string-equal (uri-scheme uri) "http"))
        (values (make-uri :scheme "http" :host (address-string address) :port (uri-port uri)
                          :path (or (uri-path uri) "/") :query (uri-query uri))
                (cons (cons "Host" (host-header uri)) headers))
        (values url headers))))

(defmethod send-webhook (url payload headers address)
  (handler-case
      (multiple-value-bind (target headers) (connection-target url address headers)
        (multiple-value-bind (body status)
            (dexador:request target :method :post
                                    :headers (cons '("Content-Type" . "application/json") headers)
                                    :content payload :connect-timeout 5 :read-timeout 10 :max-redirects 0)
          (values status body nil)))
    (http-request-failed (e)
      (values (response-status e) (response-body e) nil))
    (error (e)
      (let ((message (princ-to-string e)))
        (format *error-output* "~&[koya] webhook ~a failed: ~a~%" url message)
        (values nil nil message)))))

(defmethod resolve-host (host)
  (handler-case (get-hosts-by-name host)
    (error () '())))
