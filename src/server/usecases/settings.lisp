(defpackage #:koya-server/usecases/settings
  (:use #:cl)
  (:import-from #:local-time #:+utc-zone+)
  (:import-from #:koya-server/domain/timezone #:find-timezone #:timezone-name-p)
  (:import-from #:koya-server/usecases/ports/settings #:get-setting #:set-setting #:delete-setting)
  (:import-from #:koya-server/domain/totp #:code-step #:time-step #:unix-now)
  (:import-from #:koya-server/usecases/ports/sessions #:delete-sessions)
  (:export #:display-timezone-name
           #:display-timezone
           #:set-display-timezone
           #:totp-enabled-p
           #:totp-secret
           #:enable-totp
           #:disable-totp
           #:totp-code-valid-p
           #:wrong-codes
           #:count-wrong-code))
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

(defun totp-secret ()
  (get-setting "totp_secret"))

(defun totp-enabled-p () (and (totp-secret) t))

(defun enable-totp (secret &key keep-session)
  (set-setting "totp_secret" secret)
  (delete-sessions :except keep-session)
  secret)

(defun disable-totp (&key keep-session)
  (delete-setting "totp_secret")
  (delete-setting "totp_last_step")
  (delete-setting "totp_wrong_codes")
  (delete-sessions :except keep-session))

(defun used-step ()
  (let ((value (get-setting "totp_last_step")))
    (if value (parse-integer value) -1)))

(defun totp-code-valid-p (code &key (secret (totp-secret)) (time (unix-now)))
  (let ((step (code-step code secret :time time :after (used-step))))
    (when step
      (set-setting "totp_last_step" (princ-to-string step))
      t)))

(defun wrong-codes (&optional (time (unix-now)))
  (let ((value (get-setting "totp_wrong_codes")))
    (destructuring-bind (&optional step count) (and value (mapcar #'parse-integer (uiop:split-string value)))
      (if (eql step (time-step time)) count 0))))

(defun count-wrong-code (&optional (time (unix-now)))
  (set-setting "totp_wrong_codes" (format nil "~a ~a" (time-step time) (1+ (wrong-codes time)))))
