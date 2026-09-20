(defpackage #:koya-server/pages/login
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/lib/auth #:session-login #:login-locked-p #:note-login-failure #:clear-login-failures)
  (:import-from #:lack/request #:request-remote-addr)
  (:import-from #:koya-server/lib/totp #:totp-enabled-p)
  (:import-from #:koya-server/lib/assets #:asset-url)
  (:import-from #:koya-server/lib/page #:owner-p #:set-title #:redirect-to #:param #:same-origin-p #:~icon)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/login)

(defcomp ~login-form (&key error)
  (hsx
   (main :class "mx-auto max-w-sm px-4 py-24"
     (h1 :class "mb-6 flex items-center gap-3 text-2xl font-bold tracking-tight"
       (img :src (asset-url "icon.svg") :alt "" :width "32" :height "32" :class "h-8 w-8 rounded-md")
       "koya")
     (form :method "post" :action "/login" :class "space-y-4"
       (div
         (label :for "secret" :class "label" "Owner secret")
         (input :type "password" :id "secret" :name "secret" :required t :autofocus t :class "input mt-1.5"))
       (when (totp-enabled-p)
         (hsx (div
                (label :for "code" :class "label" "One-time code")
                (input :type "text" :id "code" :name "code" :inputmode "numeric" :autocomplete "one-time-code"
                       :pattern "[0-9 ]*" :required t :class "input mt-1.5"))))
       (when error (hsx (p :class "text-sm text-danger" error)))
       (button :type "submit" :class "btn btn-primary w-full justify-center" (~icon :name :login) "Log in")))))

(defun @get (params)
  (declare (ignore params))
  (set-title "Log in · koya")
  (if (owner-p)
      (redirect-to "/" 302)
      (hsx (~login-form))))

(defun @post (params)
  (set-title "Log in · koya")
  (cond ((not (same-origin-p))
         (set-response-status 403)
         (hsx (~login-form :error "Cross-origin request rejected")))
        ((login-locked-p (request-remote-addr ningle:*request*))
         ;; 403, not 429: Woo has no status line for 429 and fails to write the response
         (set-response-status 403)
         (hsx (~login-form :error "Too many attempts. Wait a few minutes and try again.")))
        (t
         (let* ((address (request-remote-addr ningle:*request*))
                (result (session-login (or (param params "secret") "") (param params "code"))))
           (cond ((eq result t)
                  (clear-login-failures address)
                  (redirect-to "/"))
                 (t
                  (note-login-failure address)
                  (set-response-status 401)
                  ;; one message for both factors: not saying which one was wrong
                  (hsx (~login-form :error (if (totp-enabled-p)
                                                "Wrong secret or one-time code"
                                                "Wrong secret")))))))))
