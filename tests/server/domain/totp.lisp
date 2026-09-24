(defpackage #:koya-tests/server/domain/totp
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/totp
                #:base32-decode #:base32-encode #:hotp #:totp #:generate-totp-secret
                #:otpauth-uri)
  (:import-from #:babel #:string-to-octets #:octets-to-string))
(in-package #:koya-tests/server/domain/totp)

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

(deftest setup-helpers
  (let ((secret (generate-totp-secret)))
    (ok (= (length secret) 32) "160 bits of Base32")
    (ok (= (length (base32-decode secret)) 20))
    (ok (search (format nil "secret=~a" secret) (otpauth-uri secret)))
    (ok (search "otpauth://totp/koya:owner?" (otpauth-uri secret)))))
