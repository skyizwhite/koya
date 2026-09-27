(defpackage #:koya-server/usecases/webhooks
  (:use #:cl)
  (:import-from #:koya-core/schema #:model-name #:webhook-covers-p #:webhook-label #:webhook-url)
  (:import-from #:koya-server/usecases/ports/spaces #:space-webhooks)
  (:import-from #:quri #:uri #:uri-host)
  (:import-from #:koya-server/domain/address #:addresses-reach)
  (:import-from #:koya-server/usecases/ports/webhooks
                #:record-delivery #:send-webhook #:resolve-host #:list-deliveries #:count-deliveries
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

(defparameter +events+ '(:publish :unpublish :delete :draft :discard))

(defun webhooks-for (space-name model)
  (let ((name (model-name model)))
    (remove-if-not (lambda (hook) (webhook-covers-p hook name)) (space-webhooks space-name))))

(defvar *webhook-async* t)

(defun ok-status-p (status)
  (and (integerp status) (<= 200 status 299)))

(defun elapsed-ms (start)
  (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second))

(defun url-host (url)
  (let ((host (ignore-errors (uri-host (uri url)))))
    (and host (plusp (length host)) (string-trim "[]" host))))

(defun url-reach (url)
  (let* ((host (url-host url))
         (addresses (and host (resolve-host host)))
         (reach (addresses-reach addresses)))
    (case reach
      ((nil) (values nil (if host (format nil "~a does not resolve" host) "The URL has no host")))
      (:forbidden (values nil (format nil "~a is a link-local, multicast or reserved address, which is never sent to" host)))
      (t (values reach nil (first addresses))))))

(defun send-and-log (hook space model id event payload headers)
  (let ((start (get-internal-real-time))
        (status nil) (body nil) (failure nil) (location nil))
    (handler-case
        (multiple-value-bind (reach refusal address) (url-reach (webhook-url hook))
          (if refusal
              (setf failure refusal)
              (progn
                (multiple-value-setq (status body failure location)
                  (send-webhook (webhook-url hook) payload headers address))
                (when (eq reach :internal) (setf body nil location nil))
                (when (and (null failure) (member status '(301 302 303 307 308)))
                  (setf failure (cond ((eq reach :internal) "Redirected; where to is not kept for an internal address")
                                      (location (format nil "Redirected to ~a; change the webhook URL to go there" location))
                                      (t "Redirected, with no Location")))))))
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

