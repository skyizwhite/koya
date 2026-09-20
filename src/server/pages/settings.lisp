(defpackage #:koya-server/pages/settings
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:ningle #:context)
  (:import-from #:koya-server/lib/totp
                #:totp-enabled-p #:totp-env-secret #:totp-secret #:totp-code-valid-p
                #:generate-totp-secret #:otpauth-uri #:enable-totp #:disable-totp)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:param #:set-flash #:redirect-to #:~layout #:~icon)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/settings)

;;; Instance settings. Two-factor login is set up here: a fresh secret is kept in
;;; the session until the owner proves the authenticator has it by entering a
;;; current code; only then is it stored and enforced.

(defun pending-secret () (gethash "totp_pending" (context :session)))
(defun (setf pending-secret) (value)
  (if value
      (setf (gethash "totp_pending" (context :session)) value)
      (remhash "totp_pending" (context :session))))

(defcomp ~code-input (&key (label "Current code from your authenticator"))
  (hsx (div
         (label :for "code" :class "label" label)
         (input :type "text" :id "code" :name "code" :inputmode "numeric" :autocomplete "one-time-code"
                :pattern "[0-9 ]*" :required t :autofocus t :class "input mt-1.5 max-w-xs"))))

(defcomp ~two-factor (&key pending error)
  (hsx
   (section :class "rounded-md border border-line bg-panel p-6"
     (h2 :class "mb-1 text-lg font-bold" "Two-factor login")
     (p :class "mb-4 text-sm text-muted"
       "Ask for a one-time code from an authenticator app in addition to the owner secret when logging in.")
     (when error (hsx (p :class "mb-4 text-sm text-danger" error)))
     (cond
       ((totp-env-secret)
        (hsx (p :class "text-sm" (span :class "badge bg-ok/10 text-ok" "Enabled")
               " by the " (code "KOYA_TOTP_SECRET") " environment variable. Change or unset it there.")))
       ((totp-enabled-p)
        (hsx (<>
               (p :class "mb-4 text-sm" (span :class "badge bg-ok/10 text-ok" "Enabled"))
               (form :method "post" :class "space-y-3"
                 (input :type "hidden" :name "action" :value "disable")
                 (~code-input :label "Enter a current code to turn it off")
                 (button :type "submit" :class "btn btn-danger" (~icon :name :close) "Disable two-factor login")))))
       (pending
        (hsx (<>
               (p :class "mb-4 text-sm" "Scan the QR code with your authenticator app, or enter the secret by hand, then type the code it shows to finish.")
               (div :class "mb-4 flex flex-wrap items-start gap-6"
                 (div :class "rounded-md border border-line bg-white p-2" :data-qr (otpauth-uri pending))
                 (dl :class "space-y-2 text-sm"
                   (dt :class "text-muted" "Secret")
                   (dd (code :class "select-all break-all" pending))
                   (dt :class "text-muted" "otpauth URI")
                   (dd (code :class "select-all break-all text-xs" (otpauth-uri pending)))))
               (form :method "post" :class "space-y-3"
                 (input :type "hidden" :name "action" :value "enable")
                 (~code-input :label "Code shown by the app")
                 (div :class "flex gap-2"
                   (button :type "submit" :class "btn btn-primary" (~icon :name :check) "Enable two-factor login")
                   (button :type "submit" :name "action" :value "cancel" :class "btn" (~icon :name :close) "Cancel"))))))
       (t
        (hsx (<>
               (p :class "mb-4 text-sm" (span :class "badge bg-line text-muted" "Disabled"))
               (form :method "post"
                 (input :type "hidden" :name "action" :value "begin")
                 (button :type "submit" :class "btn btn-primary" (~icon :name :shield) "Set up two-factor login")))))))))

(defcomp ~settings-page (&key pending error)
  (hsx (~layout :crumbs (list (cons "Settings" nil))
         (h1 :class "mb-6 text-2xl font-bold" "Settings")
         (~two-factor :pending pending :error error))))

(defun @get (params)
  (declare (ignore params))
  (with-owner
    (set-title "Settings · koya")
    (hsx (~settings-page :pending (pending-secret)))))

(defun @post (params)
  (with-owner-post
    (set-title "Settings · koya")
    (let ((action (param params "action")))
      (cond
        ((totp-env-secret)
         (set-response-status 400)
         (hsx (~settings-page :error "Two-factor login is configured by KOYA_TOTP_SECRET and cannot be changed here.")))
        ((equal action "begin")
         (setf (pending-secret) (generate-totp-secret))
         (redirect-to "/settings"))
        ((equal action "cancel")
         (setf (pending-secret) nil)
         (redirect-to "/settings"))
        ((equal action "enable")
         (let ((pending (pending-secret)))
           (cond ((null pending) (redirect-to "/settings"))
                 ((totp-code-valid-p (param params "code") :secret pending)
                  (enable-totp pending)
                  (setf (pending-secret) nil)
                  (set-flash "Two-factor login is on. Keep the secret somewhere safe.")
                  (redirect-to "/settings"))
                 (t (set-response-status 422)
                    (hsx (~settings-page :pending pending :error "That code did not match. Check the app and try again."))))))
        ((equal action "disable")
         (cond ((not (totp-enabled-p)) (redirect-to "/settings"))
               ((totp-code-valid-p (param params "code"))
                (disable-totp)
                (set-flash "Two-factor login is off.")
                (redirect-to "/settings"))
               (t (set-response-status 422)
                  (hsx (~settings-page :error "That code did not match; two-factor login is still on.")))))
        (t (set-response-status 400) (hsx (~settings-page :error "Unknown action")))))))
