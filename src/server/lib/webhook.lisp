(defpackage #:koya-server/lib/webhook
  (:use #:cl)
  (:import-from #:koya/core/json
                #:jobject #:to-json #:json-null)
  (:import-from #:koya/core/schema
                #:space-webhooks)
  (:import-from #:dexador)
  (:import-from #:bordeaux-threads-2
                #:make-thread)
  (:export #:notify-webhooks
           #:*webhook-sender*))
(in-package #:koya-server/lib/webhook)

;;; Content change notifications, microCMS-shaped so existing receivers keep working:
;;; {"service": SPACE, "api": MODEL, "id": ID, "type": "new"|"edit"|"delete",
;;;  "contents": {"old": {...}|null, "new": {...}|null}}

(defun default-sender (url payload)
  (handler-case
      (dexador:post url :headers '(("Content-Type" . "application/json")) :content payload
                        :connect-timeout 5 :read-timeout 10)
    (error (e)
      (format *error-output* "~&[koya] webhook ~a failed: ~a~%" url e))))

(defvar *webhook-sender* #'default-sender
  "Function (URL PAYLOAD-STRING) that delivers one webhook. Rebound in tests.")

(defun notify-webhooks (space model id type &key old new (async t))
  "Send a notification to every webhook of SPACE (a space-def). Delivery is
asynchronous unless ASYNC is NIL."
  (let ((urls (space-webhooks space)))
    (when urls
      (let ((payload (to-json (jobject "service" (koya/core/schema:space-name space)
                                       "api" model
                                       "id" id
                                       "type" type
                                       "contents" (jobject "old" (or old json-null) "new" (or new json-null))))))
        (flet ((send () (dolist (url urls) (funcall *webhook-sender* url payload))))
          (if async
              (make-thread #'send :name "koya-webhook")
              (send)))))))
