(defpackage #:koya-server/web/ui/toast
  (:use #:cl #:hsx)
  (:import-from #:jingle
                #:set-response-status #:set-response-header #:context)
  (:import-from #:koya-core/json
                #:json-array)
  (:import-from #:koya-server/domain/errors
                #:koya-error-message)
  (:import-from #:koya-server/web/http
                #:error-status)
  (:export #:set-toast
           #:take-toast
           #:~toast
           #:~toast-oob
           #:action-refusal
           #:action-refused))
(in-package #:koya-server/web/ui/toast)

(defun set-toast (message &optional (kind :ok))
  (let ((session (context :session)))
    (when session (setf (gethash "toast" session) (json-array message (string-downcase kind))))))

(defun take-toast ()
  (let* ((session (context :session))
         (toast (and session (gethash "toast" session))))
    (when (and toast (= (length toast) 2))
      (remhash "toast" session)
      (values (aref toast 0) (if (equal (aref toast 1) "error") :error :ok)))))

(defcomp ~toast (&key message (kind :ok) oob)
  (let ((error (eq kind :error)))
    (hsx
     (div :id "toast" :hx-swap-oob (and oob "true")
          :class "pointer-events-none fixed inset-x-4 top-4 z-50 flex justify-center"
       (when message
         (hsx (div :role (if error "alert" "status")
                   :class (clsx "toast pointer-events-none w-full rounded-md border bg-panel px-4 py-3 text-sm shadow-lg sm:pointer-events-auto sm:w-auto sm:max-w-md"
                                (if error "toast-long border-danger/40 text-danger" "border-ok/40 text-ok"))
                message)))))))

(defcomp ~toast-oob (&key message (kind :ok))
  (hsx (~toast :message message :kind kind :oob t)))

(defun action-refusal (message &optional (status 400))
  (set-response-status status)
  (set-response-header :hx-reswap "none")
  (hsx (~toast-oob :message message :kind :error)))

(defun action-refused (condition)
  (action-refusal (koya-error-message condition) (error-status condition)))
