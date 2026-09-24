(defpackage #:koya-server/usecases/webhooks/notify
  (:use #:cl)
  (:import-from #:koya/core/json
                #:jobject #:to-json #:json-null)
  (:import-from #:koya/core/schema
                #:model-name #:webhook-covers-p
                #:webhook-label #:webhook-url)
  (:import-from #:koya-server/usecases/ports/spaces #:space-webhooks)
  (:import-from #:koya-server/usecases/ports/webhooks #:record-delivery #:send-webhook)
  (:import-from #:bordeaux-threads-2
                #:make-thread)
  (:export #:notify-webhooks
           #:*webhook-async*))
(in-package #:koya-server/usecases/webhooks/notify)

;;; Content change notifications:
;;; {"space": SPACE, "model": MODEL, "id": ID, "event": "publish"|"unpublish"|"delete"|"draft",
;;;  "contents": {"old": {...}|null, "new": {...}|null}}
;;; Every webhook gets every event for every model it covers ("only" narrows it),
;;; and the receiver decides what to act on. What came back is recorded for the
;;; admin UI's log (usecases/webhooks/log).

(defparameter +events+ '(:publish :unpublish :delete :draft))

(defun webhooks-for (space-name model)
  "The webhooks of the space that cover MODEL."
  (let ((name (model-name model)))
    (remove-if-not (lambda (hook) (webhook-covers-p hook name)) (space-webhooks space-name))))

(defvar *webhook-async* t
  "Deliver webhooks from a background thread. Tests bind this to NIL.")

(defun ok-status-p (status)
  (and (integerp status) (<= 200 status 299)))

(defun elapsed-ms (start)
  (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second))

(defun send-and-log (hook space model id event payload headers)
  "Deliver one webhook and record what came back. Neither a failed call nor a
failed write may stop the hooks queued behind it."
  (let ((start (get-internal-real-time))
        (status nil) (body nil) (failure nil))
    (handler-case
        (multiple-value-setq (status body failure)
          (send-webhook (webhook-url hook) payload headers))
      (error (e) (setf status nil body nil failure (princ-to-string e))))
    (handler-case
        (record-delivery space
                         :label (webhook-label hook)
                         :url (webhook-url hook)
                         :model model
                         :event event
                         :content-id id
                         :ok (and (null failure) (ok-status-p status))
                         :status (and (integerp status) status)
                         :response body
                         :error failure
                         :duration-ms (elapsed-ms start))
      (error (e) (format *error-output* "~&[koya] webhook log failed: ~a~%" e)))))

(defun notify-webhooks (space-name model id event &key old new (async *webhook-async*) secret)
  "Send EVENT (one of +EVENTS+) for content ID to the webhooks of the space named
SPACE-NAME and of MODEL (a model struct). SECRET, when given, is sent as the
X-KOYA-WEBHOOK-KEY header so receivers can authenticate the call. Delivery is
asynchronous unless ASYNC is NIL."
  (assert (member event +events+))
  (let ((hooks (webhooks-for space-name model))
        (headers (and secret (list (cons "X-KOYA-WEBHOOK-KEY" secret)))))
    (when hooks
      (let* ((model-name (model-name model))
             (event-name (string-downcase (symbol-name event)))
             (payload (to-json (jobject "space" space-name
                                        "model" model-name
                                        "id" id
                                        "event" event-name
                                        "contents" (jobject "old" (or old json-null) "new" (or new json-null))))))
        (flet ((send ()
                 (dolist (hook hooks)
                   (send-and-log hook space-name model-name id event-name payload headers))))
          (if async
              (make-thread #'send :name "koya-webhook")
              (send)))))))
