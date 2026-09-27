(defpackage #:koya-server/usecases/webhooks
  (:use #:cl)
  (:import-from #:koya-core/schema #:model-name #:webhook-covers-p #:webhook-label #:webhook-url)
  (:import-from #:koya-server/usecases/ports/spaces #:space-webhooks)
  (:import-from #:koya-server/usecases/ports/webhooks
                #:record-delivery #:send-webhook #:list-deliveries #:count-deliveries
                #:find-delivery #:delivery-labels #:delivery-models #:+deliveries-kept+)
  (:import-from #:koya-server/usecases/ports/presenters #:webhook-payload)
  (:import-from #:bordeaux-threads-2 #:make-thread)
  (:export #:space-webhooks
           #:notify-webhooks
           #:*webhook-async*
           #:list-deliveries
           #:count-deliveries
           #:find-delivery
           #:delivery-labels
           #:delivery-models
           #:+deliveries-kept+))
(in-package #:koya-server/usecases/webhooks)

(defparameter +events+ '(:publish :unpublish :delete :draft))

(defun webhooks-for (space-name model)
  (let ((name (model-name model)))
    (remove-if-not (lambda (hook) (webhook-covers-p hook name)) (space-webhooks space-name))))

(defvar *webhook-async* t)

(defun ok-status-p (status)
  (and (integerp status) (<= 200 status 299)))

(defun elapsed-ms (start)
  (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second))

(defun send-and-log (hook space model id event payload headers)
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
  (assert (member event +events+))
  (let ((hooks (webhooks-for space-name model))
        (headers (and secret (list (cons "X-KOYA-WEBHOOK-KEY" secret)))))
    (when hooks
      (let* ((model-name (model-name model))
             (event-name (string-downcase (symbol-name event)))
             (payload (webhook-payload space-name model-name id event old new)))
        (flet ((send ()
                 (dolist (hook hooks)
                   (send-and-log hook space-name model-name id event-name payload headers))))
          (if async
              (make-thread #'send :name "koya-webhook")
              (send)))))))

