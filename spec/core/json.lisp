(defpackage #:koya-spec/core/json
  (:use #:cl #:rove)
  (:import-from #:koya-core/json #:parse-json #:json-parse-error #:jget #:json-array-p #:blank-p #:copy-object))
(in-package #:koya-spec/core/json)

(deftest text-that-is-not-json
  (ok (signals (parse-json "{x") 'json-parse-error) "is a json-parse-error, whatever parses it"))

(deftest an-array
  (ok (json-array-p (parse-json "[1, 2]")) "is a vector")
  (ng (json-array-p "ab") "but a string is not one")
  (ng (json-array-p nil) "nor is nothing"))

(deftest blank
  (ok (blank-p nil) "nil is blank")
  (ok (blank-p "") "and so is an empty string")
  (ng (blank-p " ") "a space is not"))

(deftest copying-an-object
  (let* ((object (parse-json "{\"a\": 1, \"b\": {\"c\": 2}}"))
         (copy (copy-object object)))
    (ok (and (not (eq copy object)) (= (jget copy "a") 1)) "gives a new object with the same keys")
    (setf (gethash "a" copy) 3)
    (ok (= (jget object "a") 1) "which changes apart from the original")
    (ok (eq (jget copy "b") (jget object "b")) "and shares what it holds"))
  (ok (zerop (hash-table-count (copy-object nil))) "nothing gives an empty object"))
