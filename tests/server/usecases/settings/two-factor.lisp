(defpackage #:koya-tests/server/usecases/settings/two-factor
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/settings/two-factor #:totp-code-valid-p #:*totp-last-counter*)
  (:import-from #:koya-server/domain/totp #:totp))
(in-package #:koya-tests/server/usecases/settings/two-factor)

;; RFC 4226 / RFC 6238 test secret: the ASCII string 12345678901234567890
(defparameter *rfc-secret* "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")

(deftest validation
  (let ((*totp-last-counter* -1))
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
        "spaces typed between digit groups are fine")))
