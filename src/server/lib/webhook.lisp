(defpackage #:koya-server/lib/webhook
  (:use #:cl)
  (:import-from #:koya/core/json
                #:jobject #:to-json #:json-null)
  (:import-from #:koya/core/schema
                #:space-webhooks #:space-name #:model-webhooks #:model-name
                #:webhook-label #:webhook-url)
  (:import-from #:dexador)
  (:import-from #:bordeaux-threads-2
                #:make-thread)
  (:export #:notify-webhooks
           #:*webhook-sender*
           #:*webhook-async*))
(in-package #:koya-server/lib/webhook)

;;; Content change notifications:
;;; {"service": SPACE, "api": MODEL, "id": ID, "event": "publish"|"unpublish"|"delete"|"draft",
;;;  "contents": {"old": {...}|null, "new": {...}|null}}
;;; Every webhook of the space, and of the model, gets every event; the receiver
;;; reads "event" and decides what to do (a revalidation hook ignores "draft").

(defun default-sender (url payload headers)
  (handler-case
      (dexador:post url :headers (cons '("Content-Type" . "application/json") headers) :content payload
                        :connect-timeout 5 :read-timeout 10)
    (error (e)
      (format *error-output* "~&[koya] webhook ~a failed: ~a~%" url e))))

(defparameter +events+ '(:publish :unpublish :delete :draft))

(defun webhooks-for (space model)
  "The webhooks of SPACE plus those of MODEL."
  (append (space-webhooks space) (and model (model-webhooks model))))

(defvar *webhook-sender* #'default-sender
  "Function (URL PAYLOAD-STRING HEADERS-ALIST) that delivers one webhook. Rebound in tests.")

(defvar *webhook-async* t
  "Deliver webhooks from a background thread. Tests bind this to NIL.")

(defun notify-webhooks (space model id event &key old new (async *webhook-async*) secret)
  "Send EVENT (one of +EVENTS+) for content ID to the webhooks of SPACE (a
space-def) and MODEL (a model struct). SECRET, when given, is sent as the
X-KOYA-WEBHOOK-KEY header so receivers can authenticate the call. Delivery is
asynchronous unless ASYNC is NIL."
  (assert (member event +events+))
  (let ((hooks (webhooks-for space model))
        (headers (and secret (list (cons "X-KOYA-WEBHOOK-KEY" secret)))))
    (when hooks
      (let ((payload (to-json (jobject "service" (space-name space)
                                       "api" (model-name model)
                                       "id" id
                                       "event" (string-downcase (symbol-name event))
                                       "contents" (jobject "old" (or old json-null) "new" (or new json-null))))))
        (flet ((send ()
                 (dolist (hook hooks)
                   (funcall *webhook-sender* (webhook-url hook) payload headers))))
          (if async
              (make-thread #'send :name "koya-webhook")
              (send)))))))
