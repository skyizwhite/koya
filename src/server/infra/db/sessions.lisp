(defpackage #:koya-server/infra/db/sessions
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch-one #:col)
  (:import-from #:koya-core/json #:to-json #:parse-json)
  (:import-from #:koya-core/time #:now-iso #:iso-from-now)
  (:import-from #:lack/middleware/session/store
                #:store #:fetch-session #:store-session #:remove-session)
  (:import-from #:koya-server/usecases/ports/sessions
                #:+session-seconds+ #:make-session-store #:delete-sessions)
  (:import-from #:koya-server/usecases/ports/config #:owner-secret)
  (:import-from #:ironclad
                #:make-hmac #:update-hmac #:hmac-digest #:byte-array-to-hex-string)
  (:import-from #:babel #:string-to-octets)
  (:export #:purge-expired-sessions))
(in-package #:koya-server/infra/db/sessions)

(defstruct (session-store (:include store) (:constructor %make-session-store)))

(defmethod make-session-store ()
  (%make-session-store))

(defun row-id (sid)
  (let ((hmac (make-hmac (string-to-octets (owner-secret) :encoding :utf-8) :sha256)))
    (update-hmac hmac (string-to-octets sid :encoding :utf-8))
    (byte-array-to-hex-string (hmac-digest hmac))))

(defvar *fetched* (make-hash-table :test 'eq :weakness :key :synchronized t))

(defmethod fetch-session ((store session-store) sid)
  (let ((row (fetch-one "SELECT data FROM sessions WHERE id = ? AND expires_at > ?" (row-id sid) (now-iso))))
    (when row
      (let ((session (handler-case (parse-json (col row "data"))
                       (error () nil))))
        (when session
          (setf (gethash session *fetched*) sid))
        session))))

(defmethod store-session ((store session-store) sid session)
  (if (equal (gethash session *fetched*) sid)
      (exec "UPDATE sessions SET data = ?, expires_at = ? WHERE id = ?"
            (to-json session) (iso-from-now +session-seconds+) (row-id sid))
      (exec "INSERT INTO sessions (id, data, expires_at) VALUES (?, ?, ?)
             ON CONFLICT (id) DO UPDATE SET data = excluded.data, expires_at = excluded.expires_at"
            (row-id sid) (to-json session) (iso-from-now +session-seconds+))))

(defmethod remove-session ((store session-store) sid)
  (exec "DELETE FROM sessions WHERE id = ?" (row-id sid)))

(defmethod delete-sessions (&key except)
  (if except
      (exec "DELETE FROM sessions WHERE id <> ?" (row-id except))
      (exec "DELETE FROM sessions")))

(defun purge-expired-sessions ()
  (exec "DELETE FROM sessions WHERE expires_at <= ?" (now-iso)))
