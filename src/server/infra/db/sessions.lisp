(defpackage #:koya-server/infra/db/sessions
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch-one #:col)
  (:import-from #:koya/core/json #:to-json #:parse-json)
  (:import-from #:koya/core/time #:now-iso #:iso-from-now)
  (:import-from #:lack/middleware/session/store
                #:store #:fetch-session #:store-session #:remove-session)
  (:import-from #:koya-server/usecases/ports/sessions
                #:+session-seconds+ #:make-session-store #:purge-expired-sessions))
(in-package #:koya-server/infra/db/sessions)

;;; The owner's session lives in the database rather than in the process, so a
;;; restart or a redeploy does not log the owner out. Lack drives a store
;;; through the three generic functions below (see lack/middleware/session).
;;; A session is stored as JSON: the rows stay readable, and reading one back
;;; never evaluates what it holds. Values must therefore be JSON-representable
;;; -- strings, numbers, booleans and vectors of them.

(defstruct (session-store (:include store))
  "Lack session store backed by the sessions table.")

(defmethod fetch-session ((store session-store) sid)
  (let ((row (fetch-one "SELECT data FROM sessions WHERE id = ? AND expires_at > ?" sid (now-iso))))
    (when row
      ;; a row we cannot read is a session that no longer exists
      (handler-case (parse-json (col row "data"))
        (error () nil)))))

(defmethod store-session ((store session-store) sid session)
  (let ((data (to-json session))
        (row (fetch-one "SELECT data, expires_at FROM sessions WHERE id = ?" sid)))
    (cond ((null row)
           (exec "INSERT INTO sessions (id, data, expires_at) VALUES (?, ?, ?)"
                 sid data (iso-from-now +session-seconds+)))
          ;; unchanged and not yet halfway through its life: leave the row alone,
          ;; so a page view costs a read rather than a write
          ((and (equal data (col row "data"))
                (string< (iso-from-now (floor +session-seconds+ 2)) (col row "expires_at"))))
          (t
           (exec "UPDATE sessions SET data = ?, expires_at = ? WHERE id = ?"
                 data (iso-from-now +session-seconds+) sid)))))

(defmethod remove-session ((store session-store) sid)
  (exec "DELETE FROM sessions WHERE id = ?" sid))

(defun purge-expired-sessions ()
  "Drop the rows behind sessions that have run out. Called at startup; a session
that outlives its row is already refused by FETCH-SESSION."
  (exec "DELETE FROM sessions WHERE expires_at <= ?" (now-iso)))
