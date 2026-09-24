(defpackage #:koya-server/web/ui/toast
  (:use #:cl #:hsx)
  (:import-from #:jingle
                #:set-response-status #:set-response-header)
  (:import-from #:ningle
                #:context)
  (:import-from #:koya/core/json
                #:json-array)
  (:export #:set-toast
           #:take-toast
           #:~toast
           #:~toast-oob
           #:action-refusal))
(in-package #:koya-server/web/ui/toast)

;;; What came of what was done. An action that answers in place sends it out of
;;; band (~TOAST-OOB); one that sends the browser to another page leaves it in
;;; the session (SET-TOAST) for that page's layout to take.

;;; A session is stored as JSON (see infra/db/sessions), so the message travels as a
;;; pair of strings rather than as a list holding a keyword.

(defun set-toast (message &optional (kind :ok))
  (let ((session (context :session)))
    (when session (setf (gethash "toast" session) (json-array message (string-downcase kind))))))

(defun take-toast ()
  "Return (values message kind) once, then forget it."
  (let* ((session (context :session))
         (toast (and session (gethash "toast" session))))
    (when (and toast (= (length toast) 2))
      (remhash "toast" session)
      (values (aref toast 0) (if (equal (aref toast 1) "error") :error :ok)))))

(defcomp ~toast (&key message (kind :ok) oob)
  "What came of what was done, at the top of the screen, going by itself (.toast in
global.css): a success after a few seconds, an error after long enough to read it.
#toast is always there, empty or not, so an action's answer can put one in out of
band."
  (let ((error (eq kind :error)))
    (hsx
     (div :id "toast" :hx-swap-oob (and oob "true")
          :class "pointer-events-none fixed inset-x-4 top-4 z-50 flex justify-center"
       (when message
         (hsx (div :role (if error "alert" "status")
                   ;; on a phone it spans the top, over the header and the editor's
                   ;; bar, so taps go through it; the pointer pauses it elsewhere
                   :class (clsx "toast pointer-events-none w-full rounded-md border bg-panel px-4 py-3 text-sm shadow-lg sm:pointer-events-auto sm:w-auto sm:max-w-md"
                                (if error "toast-long border-danger/40 text-danger" "border-ok/40 text-ok"))
                message)))))))

(defcomp ~toast-oob (&key message (kind :ok))
  "The toast for an action's answer: the session's toast waits for the next page,
which a swap never renders, so the message goes out of band into the layout's #toast."
  (hsx (~toast :message message :kind kind :oob t)))

(defun action-refusal (message &optional (status 400))
  "An action's answer when it cannot do what was asked: the page stays as it is and
MESSAGE shows as the toast. htmx 4 swaps an error response in, so the reswap says not to."
  (set-response-status status)
  (set-response-header :hx-reswap "none")
  (hsx (~toast-oob :message message :kind :error)))
