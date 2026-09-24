(defpackage #:koya-server/infra/db/settings
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch-one #:col)
  (:import-from #:koya/core/time #:now-iso)
  (:import-from #:koya-server/usecases/ports/settings #:get-setting #:set-setting #:delete-setting))
(in-package #:koya-server/infra/db/settings)

;;; Instance-wide key/value settings the owner changes from the admin UI
;;; (currently the two-factor secret). Values are strings.

(defmethod get-setting (key)
  (let ((row (fetch-one "SELECT value FROM settings WHERE key = ?" key)))
    (and row (col row "value"))))

(defmethod set-setting (key value)
  (exec "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at"
        key value (now-iso))
  value)

(defmethod delete-setting (key)
  (exec "DELETE FROM settings WHERE key = ?" key))
