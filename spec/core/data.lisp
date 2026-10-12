(defpackage #:koya-spec/core/data
  (:use #:cl #:rove)
  (:import-from #:koya-core/data
                #:data-equal #:without-nulls))
(in-package #:koya-spec/core/data)

(deftest data-is-equal-whatever-order-its-keys-are-in
  (ok (data-equal (list :a 1 :b "x") (list :b "x" :a 1)))
  (ok (data-equal (list :rows (vector (list :field-id "h" :text "t"))) (list :rows (vector (list :text "t" :field-id "h"))))
      "inside rows too")
  (ok (data-equal (list :n 1) (list :n 1.0)) "a number is equal to the same number of another type")
  (ok (data-equal nil nil) "two empty objects are equal")
  (ng (data-equal (list :a 1) (list :a 1 :b 2)) "a key more is a difference")
  (ng (data-equal (list :a nil) nil) "as is a key with nil against none")
  (ng (data-equal (list :a 1) (list "a" 1)) "a string key is not the keyword")
  (ng (data-equal (list :tags #("a" "b")) (list :tags #("b" "a"))) "the order of an array is its own")
  (ng (data-equal (list :s "A") (list :s "a")) "and a string is compared as it is"))

(deftest nulls-are-taken-away
  (ok (equal (without-nulls (list :a :null :b 1)) '(:b 1)))
  (ok (equal (without-nulls (list :meta (list :title :null :image "x"))) '(:meta (:image "x"))) "inside an object")
  (ok (equalp (without-nulls (list :rows (vector (list :field-id "h" :text :null)))) (list :rows (vector (list :field-id "h"))))
      "and inside a row")
  (ok (equal (without-nulls (list :a nil)) '(:a nil)) "a false or an empty object stays"))
