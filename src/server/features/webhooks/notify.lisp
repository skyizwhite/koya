(defpackage #:koya-server/features/webhooks/notify
  (:use #:cl)
  (:import-from #:koya/core/json
                #:jobject #:to-json #:json-null)
  (:import-from #:koya/core/schema
                #:model-name #:webhook-covers-p
                #:webhook-label #:webhook-url)
  (:import-from #:koya-server/db/schema-store
                #:space-webhooks)
  (:import-from #:koya-server/db/webhook-deliveries
                #:record-delivery)
  (:import-from #:dexador)
  (:import-from #:dexador.error
                #:http-request-failed #:response-status #:response-body)
  (:import-from #:bordeaux-threads-2
                #:make-thread)
  (:export #:notify-webhooks
           #:*webhook-sender*
           #:*webhook-async*
           #:*webhook-log*))
(in-package #:koya-server/features/webhooks/notify)

;;; Content change notifications:
;;; {"space": SPACE, "model": MODEL, "id": ID, "event": "publish"|"unpublish"|"delete"|"draft",
;;;  "contents": {"old": {...}|null, "new": {...}|null}}
;;; Every webhook gets every event for every model it covers ("only" narrows it),
;;; and the receiver decides what to act on. What came back is kept in
;;; db/webhook-deliveries.

(defun default-sender (url payload headers)
  "POST PAYLOAD to URL. Returns (values STATUS BODY ERROR). A 4xx or 5xx is an
answer and carries its status and body; only a transport failure has neither."
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

(defparameter +events+ '(:publish :unpublish :delete :draft))

(defun webhooks-for (space-name model)
  "The webhooks of the space that cover MODEL."
  (let ((name (model-name model)))
    (remove-if-not (lambda (hook) (webhook-covers-p hook name)) (space-webhooks space-name))))

(defvar *webhook-sender* #'default-sender
  "Function (URL PAYLOAD-STRING HEADERS-ALIST) that delivers one webhook and
returns (values STATUS BODY ERROR). Rebound in tests.")

(defvar *webhook-async* t
  "Deliver webhooks from a background thread. Tests bind this to NIL.")

(defvar *webhook-log* t
  "Record every delivery in the database for the admin UI's webhook log.")

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
          (funcall *webhook-sender* (webhook-url hook) payload headers))
      (error (e) (setf status nil body nil failure (princ-to-string e))))
    (when *webhook-log*
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
        (error (e) (format *error-output* "~&[koya] webhook log failed: ~a~%" e))))))

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
