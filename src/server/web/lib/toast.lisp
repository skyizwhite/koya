(defpackage #:koya-server/web/lib/toast
  (:use #:cl #:hsx)
  (:export #:~toast
           #:~toast-message))
(in-package #:koya-server/web/lib/toast)

(defcomp ~toast-message (&key message (kind :ok) clickable on-init)
  (let ((error (eq kind :error)))
    (hsx (div :role (if error "alert" "status") :n-on-init on-init
              :class (clsx "toast w-full rounded-md border bg-panel px-4 py-3 text-sm shadow-lg sm:w-auto sm:max-w-md"
                           (if clickable "pointer-events-auto" "pointer-events-none sm:pointer-events-auto")
                           (if error "toast-long border-danger/40 text-danger" "border-ok/40 text-ok"))
           message))))

(defcomp ~toast (&key message (kind :ok) clickable on-init)
  (hsx
   (div :id "toast"
        :class "pointer-events-none fixed inset-x-4 top-4 z-50 flex justify-center"
     (when message
       (hsx (~toast-message :message message :kind kind :clickable clickable :on-init on-init))))))
