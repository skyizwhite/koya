(defpackage #:koya-server/usecases/settings
  (:use #:cl)
  (:import-from #:local-time #:+utc-zone+)
  (:import-from #:koya-server/domain/timezone #:find-timezone #:timezone-name-p)
  (:import-from #:koya-server/usecases/ports/settings #:get-setting #:set-setting #:delete-setting)
  (:import-from #:koya-server/domain/totp #:code-step #:unix-now)
  (:import-from #:koya-server/usecases/ports/sessions #:delete-sessions)
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

(defparameter +setting-key+ "timezone")

(defun display-timezone-name ()
  (or (get-setting +setting-key+) "UTC"))

(defun display-timezone ()
  (or (find-timezone (display-timezone-name)) +utc-zone+))

(defun set-display-timezone (name)
  (when (timezone-name-p name)
    (if (string-equal name "UTC")
        (delete-setting +setting-key+)
        (set-setting +setting-key+ name))
    name))

(defvar *totp-last-counter* -1)

(defun totp-secret ()
  (get-setting "totp_secret"))

(defun totp-enabled-p () (and (totp-secret) t))

(defun enable-totp (secret &key keep-session)
  (set-setting "totp_secret" secret)
  (setf *totp-last-counter* -1)
  (delete-sessions :except keep-session)
  secret)

(defun disable-totp (&key keep-session)
  (delete-setting "totp_secret")
  (setf *totp-last-counter* -1)
  (delete-sessions :except keep-session))

(defun totp-code-valid-p (code &key (secret (totp-secret)) (time (unix-now)))
  (let ((step (code-step code secret :time time :after *totp-last-counter*)))
    (when step
      (setf *totp-last-counter* step)
      t)))
