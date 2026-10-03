(defpackage #:koya-server/infra/db/sessions
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch-one #:col)
  (:import-from #:koya-core/json #:to-json #:parse-json)
  (:import-from #:koya-core/time #:now-iso #:iso-from-now)
  (:import-from #:lack/middleware/session/store
                #:store #:fetch-session #:store-session #:remove-session)
  (:import-from #:koya-server/usecases/ports/sessions
                #:+session-seconds+ #:make-session-store)
  (:export #:purge-expired-sessions))
(in-package #:koya-server/infra/db/sessions)

(defstruct (session-store (:include store) (:constructor %make-session-store)))

(defmethod make-session-store ()
  (%make-session-store))

(defmethod fetch-session ((store session-store) sid)
  (let ((row (fetch-one "SELECT data FROM sessions WHERE id = ? AND expires_at > ?" sid (now-iso))))
    (when row
      (handler-case (parse-json (col row "data"))
        (error () nil)))))

(defmethod store-session ((store session-store) sid session)
  (exec "INSERT INTO sessions (id, data, expires_at) VALUES (?, ?, ?)
         ON CONFLICT (id) DO UPDATE SET data = excluded.data, expires_at = excluded.expires_at"
        sid (to-json session) (iso-from-now +session-seconds+)))

(defmethod remove-session ((store session-store) sid)
  (exec "DELETE FROM sessions WHERE id = ?" sid))

(defun purge-expired-sessions ()
  (exec "DELETE FROM sessions WHERE expires_at <= ?" (now-iso)))
