(defpackage #:koya-tests/core/ulid
  (:use #:cl #:rove)
  (:import-from #:koya/core/ulid
                #:make-ulid
                #:ulid-p
                #:ulid-timestamp))
(in-package #:koya-tests/core/ulid)

(deftest make-ulid
  (let ((id (make-ulid)))
    (ok (= (length id) 26))
    (ok (ulid-p id))
    (ok (string/= id (make-ulid)) "two ulids differ"))
  (testing "embeds the timestamp and sorts by it"
    (let ((a (make-ulid 1000))
          (b (make-ulid 2000)))
      (ok (= (ulid-timestamp a) 1000))
      (ok (= (ulid-timestamp b) 2000))
      (ok (string< a b))))
  (testing "max timestamp encodes to 7ZZZZZZZZZ"
    (ok (string= (subseq (make-ulid (1- (expt 2 48))) 0 10) "7ZZZZZZZZZ"))))

(deftest ulid-p
  (ok (ulid-p "01ARZ3NDEKTSV4RRFFQ69G5FAV"))
  (ok (ulid-p "01arz3ndektsv4rrffq69g5fav") "lowercase accepted")
  (ng (ulid-p "01ARZ3NDEKTSV4RRFFQ69G5FA") "too short")
  (ng (ulid-p "81ARZ3NDEKTSV4RRFFQ69G5FAV") "overflow first char")
  (ng (ulid-p "01ARZ3NDEKTSV4RRFFQ69G5FAI") "I is not in the alphabet")
  (ng (ulid-p nil))
  (ng (ulid-p 42)))
