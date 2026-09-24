(defpackage #:koya-server/lib/totp
  (:use #:cl)
  (:import-from #:koya-server/domain/totp
                #:code-step #:unix-now)
  (:import-from #:koya-server/db/settings
                #:get-setting #:set-setting #:delete-setting)
  (:export #:totp-enabled-p
           #:totp-secret
           #:enable-totp
           #:disable-totp
           #:totp-code-valid-p
           #:*totp-last-counter*))
(in-package #:koya-server/lib/totp)

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
