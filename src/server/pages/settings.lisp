(defpackage #:koya-server/pages/settings
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:ningle #:context)
  (:import-from #:koya-server/lib/totp
                #:totp-enabled-p #:totp-env-secret #:totp-secret #:totp-code-valid-p
                #:generate-totp-secret #:otpauth-uri #:enable-totp #:disable-totp)
  (:import-from #:koya-server/lib/timezone
                #:display-timezone-name #:set-display-timezone #:timezone-names #:format-local)
  (:import-from #:koya/core/time #:now-iso)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:param #:set-flash #:redirect-to
                #:~layout #:~icon)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/settings)

;;; Instance settings: what holds for the whole server rather than one space.
;;; Keys are not here -- they belong to a space and are made on its keys page.
;;; Two-factor login is set up here: a fresh secret is kept in
;;; the session until the owner proves the authenticator has it by entering a
;;; current code; only then is it stored and enforced. The time zone is the one
;;; every page shows times in; storage and the delivery API stay UTC.

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

(defcomp ~time-zone (&key error)
  (hsx
   (section :class "rounded-md border border-line bg-panel p-6"
     (h2 :class "mb-1 text-lg font-bold" "Time zone")
     (p :class "mb-4 text-sm text-muted"
       "Times in the admin UI — created and updated at, datetime fields — are shown and entered in this zone. "
       "Stored values and the delivery API stay UTC.")
     (when error (hsx (p :class "mb-4 text-sm text-danger" error)))
     (form :method "post" :class "flex flex-wrap items-end gap-3"
       (input :type "hidden" :name "action" :value "timezone")
       (div
         (label :for "timezone" :class "label" "IANA name")
         (input :type "text" :id "timezone" :name "timezone" :list "timezones" :required t :autocomplete "off"
                :value (display-timezone-name) :placeholder "Asia/Tokyo" :class "input mt-1.5 w-64"))
       (datalist :id "timezones"
         (loop :for name :in (timezone-names) :collect (hsx (option :value name))))
       (button :type "submit" :class "btn btn-primary" (~icon :name :check) "Save"))
     (p :class "mt-3 text-xs text-muted" "Now: " (format-local (now-iso))))))

(defcomp ~settings-page (&key pending error timezone-error)
  (hsx (~layout :crumbs (list (cons "Settings" nil))
         (h1 :class "mb-6 text-2xl font-bold" "Settings")
         (div :class "space-y-6"
           (~time-zone :error timezone-error)
           (~two-factor :pending pending :error error)))))

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
        ((equal action "timezone")
         (let ((name (string-trim " " (or (param params "timezone") ""))))
           (cond ((set-display-timezone name)
                  (set-flash (format nil "Times are now shown in ~a." name))
                  (redirect-to "/settings"))
                 (t (set-response-status 422)
                    (hsx (~settings-page :pending (pending-secret)
                                         :timezone-error (format nil "~s is not a time zone this server knows. Use an IANA name such as Asia/Tokyo, or UTC." name)))))))
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
