(defpackage #:koya-spec/server/usecases/settings
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/settings #:totp-code-valid-p #:enable-totp #:disable-totp)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db #:exec)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/domain/totp #:totp))
(in-package #:koya-spec/server/usecases/settings)

(defparameter *rfc-secret* "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")

(setup
  (connect-db ":memory:")
  (migrate))

(teardown (disconnect-db))

(defhook :before (exec "DELETE FROM settings"))

(deftest validation
  (ok (totp-code-valid-p "005924" :secret *rfc-secret* :time 1234567890))
  (ng (totp-code-valid-p "005924" :secret *rfc-secret* :time 1234567890) "a code is single-use")
  (ok (totp-code-valid-p (totp *rfc-secret* :time 1234567920) :secret *rfc-secret* :time 1234567890)
      "the next step is accepted (clock skew)")
  (ng (totp-code-valid-p (totp *rfc-secret* :time (+ 1234567890 300)) :secret *rfc-secret* :time 1234567890)
      "ten steps away is not")
  (ng (totp-code-valid-p "000000" :secret *rfc-secret* :time 1234567890))
  (ng (totp-code-valid-p nil :secret *rfc-secret* :time 1234567890))
  (ok (totp-code-valid-p (format nil "~a ~a" (subseq (totp *rfc-secret* :time 1234568890) 0 3)
                                 (subseq (totp *rfc-secret* :time 1234568890) 3))
                         :secret *rfc-secret* :time 1234568890)
      "spaces typed between digit groups are fine"))

(deftest a-used-code-stays-used-after-a-restart
  (let ((path (format nil "~a/koya-spec-totp-~a.db" (string-right-trim "/" (or (uiop:getenv "TMPDIR") "/tmp"))
                      (get-universal-time))))
    (disconnect-db)
    (unwind-protect
         (progn
           (connect-db path)
           (migrate)
           (ok (totp-code-valid-p "005924" :secret *rfc-secret* :time 1234567890))
           (disconnect-db)
           (connect-db path)
           (ng (totp-code-valid-p "005924" :secret *rfc-secret* :time 1234567890)
               "the step it used is in the database, not in the process"))
      (disconnect-db)
      (uiop:delete-file-if-exists path)
      (connect-db ":memory:")
      (migrate))))

(deftest turning-two-factor-off-forgets-the-used-step
  (enable-totp *rfc-secret*)
  (ok (totp-code-valid-p "005924" :time 1234567890))
  (disable-totp)
  (ok (totp-code-valid-p (totp "JBSWY3DPEHPK3PXP" :time 1234567890) :secret "JBSWY3DPEHPK3PXP" :time 1234567890)
      "a new secret's code is taken in the same step"))
