(defpackage #:koya-server/lib/webhook
  (:use #:cl)
  (:import-from #:koya/core/json
                #:jobject #:to-json #:json-null)
  (:import-from #:koya/core/schema
                #:space-webhooks #:space-name #:model-webhooks #:model-name
                #:webhook-label #:webhook-url #:webhook-events)
  (:import-from #:dexador)
  (:import-from #:bordeaux-threads-2
                #:make-thread)
  (:export #:notify-webhooks
           #:*webhook-sender*
           #:*webhook-async*))
(in-package #:koya-server/lib/webhook)

;;; Content change notifications, microCMS-shaped so existing receivers keep working:
;;; {"service": SPACE, "api": MODEL, "id": ID, "type": "new"|"edit"|"delete"|"draft",
;;;  "contents": {"old": {...}|null, "new": {...}|null}}
;;; Each change has an EVENT (:publish :unpublish :delete :draft); a webhook is
;;; called when its events include it. The space's webhooks apply to every model,
;;; the model's own are added.

(defun default-sender (url payload headers)
  (handler-case
      (dexador:post url :headers (cons '("Content-Type" . "application/json") headers) :content payload
                        :connect-timeout 5 :read-timeout 10)
    (error (e)
      (format *error-output* "~&[koya] webhook ~a failed: ~a~%" url e))))

(defun webhooks-for (space model event)
  "The webhooks of SPACE and MODEL that subscribe to EVENT."
  (remove-if-not (lambda (hook) (member event (webhook-events hook)))
                 (append (space-webhooks space) (and model (model-webhooks model)))))

(defvar *webhook-sender* #'default-sender
  "Function (URL PAYLOAD-STRING HEADERS-ALIST) that delivers one webhook. Rebound in tests.")

(defvar *webhook-async* t
  "Deliver webhooks from a background thread. Tests bind this to NIL.")

(defun notify-webhooks (space model id type event &key old new (async *webhook-async*) secret)
  "Send a notification to the webhooks of SPACE (a space-def) and MODEL (a model
struct) that subscribe to EVENT. SECRET, when given, is sent as the
X-KOYA-WEBHOOK-KEY header so receivers can authenticate the call. Delivery is
asynchronous unless ASYNC is NIL."
  (let ((hooks (webhooks-for space model event))
        (headers (and secret (list (cons "X-KOYA-WEBHOOK-KEY" secret)))))
    (when hooks
      (let ((payload (to-json (jobject "service" (space-name space)
                                       "api" (model-name model)
                                       "id" id
                                       "type" type
                                       "contents" (jobject "old" (or old json-null) "new" (or new json-null))))))
        (flet ((send ()
                 (dolist (hook hooks)
                   (funcall *webhook-sender* (webhook-url hook) payload headers))))
          (if async
              (make-thread #'send :name "koya-webhook")
              (send)))))))
