(defpackage #:koya-spec/server/domain/number
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/number
                #:parse-decimal))
(in-package #:koya-spec/server/domain/number)

(deftest decimals
  (testing "integers stay integers, and a point or an exponent makes a double"
    (ok (eql (parse-decimal "42") 42))
    (ok (eql (parse-decimal "-7") -7))
    (ok (eql (parse-decimal "2.5") 2.5d0))
    (ok (eql (parse-decimal "-0.25") -0.25d0))
    (ok (eql (parse-decimal "1e3") 1000d0))
    (ok (eql (parse-decimal "15E-1") 1.5d0))
    (ok (eql (parse-decimal ".5") 0.5d0) "a browser's number input sends .5 as typed")
    (ok (eql (parse-decimal "-.5") -0.5d0)))
  (testing "anything else is not a number"
    (dolist (s '("" "abc" "abc123" "1/3" "#x1f" "#b101" "1 2" " 1" "1." "." "-" "e3" ".e3" "+1" "1d0" "1.5f0" "--1" "1e" "#.(+ 1 2)"))
      (ok (null (parse-decimal s)) (format nil "~s" s)))
    (ok (null (parse-decimal nil))))
  (testing "a digit of another script is not a digit"
    (ok (null (parse-decimal (string (code-char #x0663))))))
  (testing "a value too large for a double is not a number, and a tiny one is zero"
    (ok (null (parse-decimal "1e999")))
    (ok (null (parse-decimal (concatenate 'string "1" (make-string 400 :initial-element #\0) ".0"))))
    (ok (zerop (parse-decimal "1e-999"))))
  (testing "an integer is one SQLite can hold"
    (ok (eql (parse-decimal "9223372036854775807") 9223372036854775807))
    (ok (eql (parse-decimal "-9223372036854775808") -9223372036854775808))
    (ok (null (parse-decimal "9223372036854775808")))
    (ok (null (parse-decimal "123456789012345678901234567890"))))
  (testing "a number is at most 64 characters, so its digits are never many to read"
    (ok (parse-decimal (concatenate 'string "0." (make-string 62 :initial-element #\1))))
    (ok (null (parse-decimal (concatenate 'string "0." (make-string 63 :initial-element #\1)))))
    (ok (null (parse-decimal (make-string 1000000 :initial-element #\7)))))
  (testing "an exponent is at most three digits"
    (ok (null (parse-decimal "1e1000000000"))))
  (testing "nesting does not reach the reader"
    (ok (null (parse-decimal (make-string 100000 :initial-element #\()))))
  (testing "a word interns nothing"
    (parse-decimal "koyaNeverInterned")
    (ok (null (find-symbol "KOYANEVERINTERNED" :cl-user)))))
