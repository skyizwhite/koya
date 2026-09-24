(defpackage #:koya-server/usecases/settings/timezone
  (:use #:cl)
  (:import-from #:local-time
                #:+utc-zone+)
  (:import-from #:koya-server/domain/timezone
                #:find-timezone #:timezone-name-p)
  (:import-from #:koya-server/usecases/ports/settings #:get-setting #:set-setting #:delete-setting)
  (:export #:display-timezone-name
           #:display-timezone
           #:set-display-timezone))
(in-package #:koya-server/usecases/settings/timezone)

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
