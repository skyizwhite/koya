(defpackage #:koya-tests/server/totp
  (:use #:cl #:rove)
  (:import-from #:koya-server/lib/totp
                #:base32-decode #:base32-encode #:hotp #:totp #:totp-code-valid-p
                #:generate-totp-secret #:otpauth-uri #:*totp-last-counter*)
  (:import-from #:babel #:string-to-octets #:octets-to-string))
(in-package #:koya-tests/server/totp)

;; RFC 4226 / RFC 6238 test secret: the ASCII string 12345678901234567890
(defparameter *rfc-secret* "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")

(deftest base32
  (ok (string= (octets-to-string (base32-decode *rfc-secret*)) "12345678901234567890"))
  (ok (string= (base32-encode (string-to-octets "12345678901234567890")) *rfc-secret*))
  (ok (string= (base32-encode (string-to-octets "foobar")) "MZXW6YTBOI") "unpadded, per RFC 4648 test vector")
  (ok (equalp (base32-decode "mzxw 6ytb oi==") (string-to-octets "foobar")) "case, spaces and padding are ignored")
  (ok (signals (base32-decode "abc1") 'error) "1 is not Base32"))

(deftest hotp-vectors
  (let ((key (string-to-octets "12345678901234567890")))
    (ok (string= (hotp key 0) "755224"))
    (ok (string= (hotp key 1) "287082"))
    (ok (string= (hotp key 9) "520489"))))

(deftest totp-vectors
  (ok (string= (totp *rfc-secret* :time 59) "287082"))
  (ok (string= (totp *rfc-secret* :time 1111111109) "081804"))
  (ok (string= (totp *rfc-secret* :time 1234567890) "005924")))

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

(deftest setup-helpers
  (let ((secret (generate-totp-secret)))
    (ok (= (length secret) 32) "160 bits of Base32")
    (ok (= (length (base32-decode secret)) 20))
    (ok (search (format nil "secret=~a" secret) (otpauth-uri secret)))
    (ok (search "otpauth://totp/koya:owner?" (otpauth-uri secret)))))
