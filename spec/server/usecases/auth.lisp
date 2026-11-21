(defpackage #:koya-spec/server/usecases/auth
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/auth #:check-login)
  (:import-from #:koya-server/usecases/settings #:enable-totp)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/domain/totp #:totp #:generate-totp-secret)
  (:import-from #:koya-spec/server/logs #:logged))
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
      (ok (eq (check-login *secret* (wrong-code-at time) :time time) :wrong-code)))
    (ok (eq (check-login *secret* nil :time time) :wrong-code) "no code is a wrong one")
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
      (ok (eq (check-login "not the secret" (wrong-code-at time) :time time) :wrong-secret)))
    (ok (eq (check-login *secret* (code-at time) :time time) t)
        "only someone who has the secret can spend the codes")))

(deftest a-login-is-logged-without-what-was-typed
  (let ((time 1900000000))
    (testing "a login, with a timestamp and its level"
      (let ((log (logged (lambda () (check-login *secret* (code-at time) :time time)))))
        (ok (cl-ppcre:scan "^\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d \\[INFO \\] <KOYA.AUTH>: the owner logged in$"
                           (string-right-trim '(#\Newline) log)))
        (ng (search *secret* log))))
    (testing "a refused one, naming what was wrong and neither the secret nor the code"
      (let ((log (logged (lambda () (check-login "typed-secret-that-is-wrong" (code-at time) :time time)))))
        (ok (search "[WARN ] <KOYA.AUTH>: a login was refused: wrong secret" log))
        (ng (search "typed-secret-that-is-wrong" log))
        (ng (search (code-at time) log)))
      (let* ((code (wrong-code-at (+ time 60)))
             (log (logged (lambda () (check-login *secret* code :time (+ time 60))))))
        (ok (search "[WARN ] <KOYA.AUTH>: a login was refused: wrong code" log))
        (ng (search *secret* log))
        (ng (search code log))))
    (testing "and one refused for too many wrong codes"
      (let ((at (+ time 120)))
        (dotimes (i 5) (check-login *secret* (wrong-code-at at) :time at))
        (ok (search "[WARN ] <KOYA.AUTH>: a login was refused: too many wrong codes"
                    (logged (lambda () (check-login *secret* (code-at at) :time at)))))))))
