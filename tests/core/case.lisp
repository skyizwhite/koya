(defpackage #:koya-tests/core/case
  (:use #:cl #:rove)
  (:import-from #:koya/core/case
                #:camel-key
                #:kebab-keyword
                #:lisp->jvalue
                #:jvalue->lisp)
  (:import-from #:koya/core/json
                #:to-json
                #:parse-json))
(in-package #:koya-tests/core/case)

(deftest keys
  (ok (string= (camel-key :published-at) "publishedAt"))
  (ok (string= (camel-key "published-at") "publishedAt"))
  (ok (string= (camel-key "publishedAt") "publishedAt"))
  (ok (string= (camel-key 'title) "title"))
  (ok (eq (kebab-keyword "publishedAt") :published-at))
  (ok (eq (kebab-keyword "totalCount") :total-count)))

(deftest round-trip
  (let* ((lisp '(:title "Hello" :published-at "2026-01-01T00:00:00Z" :tags ("a" "b")
                 :meta (:view-count 3 :draft nil)))
         (json (to-json (lisp->jvalue lisp)))
         (back (jvalue->lisp (parse-json json))))
    (ok (search "\"publishedAt\"" json))
    (ok (search "\"viewCount\"" json))
    (ok (search "[\"a\",\"b\"]" json))
    (ok (string= (getf back :title) "Hello"))
    (ok (equal (getf back :tags) '("a" "b")))
    (ok (= (getf (getf back :meta) :view-count) 3))
    (ok (null (getf (getf back :meta) :draft)))))
