(defpackage #:koya-server/usecases/settings
  (:use #:cl)
  (:import-from #:local-time #:+utc-zone+)
  (:import-from #:koya-server/domain/timezone #:find-timezone #:timezone-name-p)
  (:import-from #:koya-server/usecases/ports/settings #:get-setting #:set-setting #:delete-setting)
  (:import-from #:koya-server/domain/totp #:code-step #:unix-now)
  (:export #:display-timezone-name
           #:display-timezone
           #:set-display-timezone
           #:totp-enabled-p
           #:totp-secret
           #:enable-totp
           #:disable-totp
           #:totp-code-valid-p
           #:*totp-last-counter*))
(in-package #:koya-server/usecases/settings)

;;; The admin UI shows and takes times in one zone the owner picks on the
;;; settings page.

(defparameter +setting-key+ "timezone")

(defun display-timezone-name ()
  (or (get-setting +setting-key+) "UTC"))

(defun display-timezone ()
  "The zone the admin UI shows times in. A stored name the system no longer knows
falls back to UTC rather than breaking every page."
  (or (find-timezone (display-timezone-name)) +utc-zone+))

(defun set-display-timezone (name)
  "Store NAME as the display zone. Returns NAME, or NIL when it is not a zone."
  (when (timezone-name-p name)
    (if (string-equal name "UTC")
        (delete-setting +setting-key+)
        (set-setting +setting-key+ name))
    name))

;;; The owner turns the second factor on from the admin UI's settings page, which
;;; stores the Base32 secret in the settings table; without one, the owner secret
;;; alone logs in.

(defvar *totp-last-counter* -1
  "Highest time step that has already logged someone in; a code is single-use.")

(defun totp-secret ()
  (get-setting "totp_secret"))

(defun totp-enabled-p () (and (totp-secret) t))

(defun enable-totp (secret)
  "Store SECRET as the second factor. Forget any step used with the previous one."
  (set-setting "totp_secret" secret)
  (setf *totp-last-counter* -1)
  secret)

(defun disable-totp ()
  (delete-setting "totp_secret")
  (setf *totp-last-counter* -1))

(defun totp-code-valid-p (code &key (secret (totp-secret)) (time (unix-now)))
  "True when CODE is the code of a step near now that has not logged in before.
Accepting a code consumes its step."
  (let ((step (code-step code secret :time time :after *totp-last-counter*)))
    (when step
      (setf *totp-last-counter* step)
      t)))
