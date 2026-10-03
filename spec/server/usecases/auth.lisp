(defpackage #:koya-spec/server/usecases/auth
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/auth #:check-login)
  (:import-from #:koya-server/usecases/settings #:enable-totp)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/domain/totp #:totp #:generate-totp-secret))
(in-package #:koya-spec/server/usecases/auth)

(defparameter *secret* "auth-spec-secret-long-enough-to-log-in")
(defparameter *totp-secret* (generate-totp-secret))
(defvar *saved-secret* nil)

(setup
  (setf *saved-secret* (uiop:getenv "KOYA_SECRET"))
  (setf (uiop:getenv "KOYA_SECRET") *secret*)
  (connect-db ":memory:")
  (migrate)
  (enable-totp *totp-secret*))

(teardown
  (disconnect-db)
  (setf (uiop:getenv "KOYA_SECRET") (or *saved-secret* "")))

(defun code-at (time) (totp *totp-secret* :time time))

(defun wrong-code-at (time)
  (if (string= (code-at time) "000000") "111111" "000000"))

(deftest wrong-codes-are-limited-each-step
  (let ((time 1800000000))
    (dotimes (i 4)
      (ok (eq (check-login *secret* (wrong-code-at time) :time time) :code)))
    (ok (eq (check-login *secret* nil :time time) :code) "no code is a wrong one")
    (ok (eq (check-login *secret* (code-at time) :time time) :too-many-codes)
        "after five wrong codes, not even the right one is taken")
    (ok (eq (check-login "not the secret" (code-at time) :time (+ time 29)) :too-many-codes)
        "and a wrong secret is told the same, so the answer says nothing of the secret")
    (ok (eq (check-login *secret* (code-at (+ time 30)) :time (+ time 30)) t)
        "the next step takes codes again")))

(deftest fewer-wrong-codes-than-the-limit-stop-nothing
  (let ((time 1800000300))
    (dotimes (i 4)
      (check-login *secret* (wrong-code-at time) :time time))
    (ok (eq (check-login *secret* (code-at time) :time time) t))))

(deftest a-wrong-secret-counts-no-code
  (let ((time 1800000600))
    (dotimes (i 10)
      (ok (null (check-login "not the secret" (wrong-code-at time) :time time))))
    (ok (eq (check-login *secret* (code-at time) :time time) t)
        "only someone who has the secret can spend the codes")))
