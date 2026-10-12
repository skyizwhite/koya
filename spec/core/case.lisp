(defpackage #:koya-spec/core/case
  (:use #:cl #:rove)
  (:import-from #:koya-core/case
                #:camel-key
                #:kebab-keyword
                #:find-kebab-keyword
                #:name-does-not-come-back
                #:lisp->jvalue
                #:jvalue->lisp
                #:jvalue->data
                #:data->jvalue)
  (:import-from #:koya-core/json
                #:to-json
                #:parse-json))
(in-package #:koya-spec/core/case)

(deftest keys
  (ok (string= (camel-key :published-at) "publishedAt"))
  (ok (string= (camel-key "published-at") "publishedAt"))
  (ok (string= (camel-key "publishedAt") "publishedAt"))
  (ok (string= (camel-key 'title) "title"))
  (ok (eq (kebab-keyword "publishedAt") :published-at))
  (ok (eq (kebab-keyword "totalCount") :total-count)))

(deftest keys-come-back-as-they-were
  (loop :for (name keyword) :in '(("eventAt" :event-at) ("pageURL" :page-u-r-l) ("pageUrl" :page-url)
                                  ("item2Name" :item2-name) ("item2name" :item2name) ("x" :x))
        :do (ok (eq (kebab-keyword name) keyword) (format nil "~a is ~s" name keyword))
            (ok (string= (camel-key keyword) name) (format nil "and ~s is ~a again" keyword name))))

(deftest a-key-is-found-without-being-interned
  (ok (eq (find-kebab-keyword "publishedAt") :published-at) "a keyword already interned is found")
  (ok (null (find-kebab-keyword "published-at")) "only by the key it converts back to")
  (ok (equalp (jvalue->data (parse-json "{\"publishedAt\": 1, \"published-at\": 2}")) (list :published-at 1 "published-at" 2))
      "so another spelling stays a string and never doubles a key")
  (ok (null (find-kebab-keyword "neverSeenBeforeName")) "one that is not stays unfound")
  (ok (null (find-symbol "NEVER-SEEN-BEFORE-NAME" :keyword)) "and is not interned by looking"))

(deftest json-values-become-data
  (let ((data (jvalue->data (parse-json "{\"publishedAt\": \"2026\", \"flag\": false, \"none\": null,
                                          \"tags\": [\"a\"], \"meta\": {\"viewCount\": 3}, \"someUnknownKeyXyz\": 1}"))))
    (ok (equalp data (list :published-at "2026" :flag nil :none :null :tags #("a") :meta (list :view-count 3)
                           "someUnknownKeyXyz" 1))
        "an object is a plist in its keys' order, an array a vector, null :null, and a key never interned stays a string")
    (ok (null (find-symbol "SOME-UNKNOWN-KEY-XYZ" :keyword))))
  (ok (equalp (jvalue->data (parse-json "{\"someStoredKeyXyz\": 1}") :intern t) (list :some-stored-key-xyz 1))
      "data koya stored has its keys interned")
  (ok (equalp (jvalue->data (parse-json "[{\"fieldId\": \"heading\"}, []]")) (vector (list :field-id "heading") #()))))

(deftest data-becomes-json-values
  (ok (string= (to-json (data->jvalue (list :published-at "2026" :flag nil :ok t :none :null :tags #("a" "b")
                                            :meta (list :view-count 3) :page-u-r-l "u")))
               "{\"publishedAt\":\"2026\",\"flag\":false,\"ok\":true,\"none\":null,\"tags\":[\"a\",\"b\"],\"meta\":{\"viewCount\":3},\"pageURL\":\"u\"}")
      "in the plist's order, with each key as it was named")
  (ok (string= (to-json (data->jvalue (vector (list :field-id "h") #()))) "[{\"fieldId\":\"h\"},[]]"))
  (ok (signals (data->jvalue (list :tags (list "a" "b")))) "a list that is not a plist is refused, as an array is a vector")
  (ok (signals (data->jvalue (list :a 1 :b))) "as is one with a key left without a value")
  (ok (signals (data->jvalue (list "unknown" 1))) "and one whose key is a string, which no field is"))

(deftest a-keyword-is-made-from-a-key-only
  (ok (signals (kebab-keyword :published-at)) "a symbol is not a key to convert"))

(deftest a-name-that-would-not-come-back-is-refused
  (ok (signals (kebab-keyword "published-at")) "a key that is not the name of its keyword is not interned")
  (ok (signals (jvalue->data (parse-json "{\"publishedAt\": 1, \"published-at\": 2}") :intern t))
      "so stored data never folds two keys into one")
  (ok (signals (camel-key :item-2)) ":item-2 would come back as :item2")
  (ok (signals (camel-key :a--b)))
  (ok (signals (camel-key "item-2")) "given as a string too")
  (flet ((refusal (thunk) (handler-case (funcall thunk) (name-does-not-come-back (c) (princ-to-string c)))))
    (ok (equal (refusal (lambda () (camel-key :item-2)))
               ":item-2 does not come back as itself: it becomes \"item2\", which comes back as :item2")
        "and says what it would become")
    (ok (equal (refusal (lambda () (camel-key :|fooBar|)))
               ":|fooBar| does not come back as itself: it becomes \"foobar\", which comes back as :foobar")
        "naming a symbol as it is written")
    (ok (equal (refusal (lambda () (kebab-keyword "item-2")))
               "\"item-2\" does not come back as itself: it becomes :item-2, which comes back as \"item2\"")
        "whichever way it is converted")
    (ok (equal (refusal (lambda () (kebab-keyword "foo:bar-x")))
               "\"foo:bar-x\" does not come back as itself: it becomes :|FOO:BAR-X|, which comes back as \"foo:barX\"")
        "writing each keyword so it could be read back"))
  (ok (signals (data->jvalue (list :item-2 1))) "and is not written")
  (ok (signals (lisp->jvalue '(:item-2 1))) "by either conversion")
  (ok (signals (jvalue->lisp (parse-json "{\"blog-post\": 1}")) 'name-does-not-come-back)
      "and a key that would not come back is not read"))

(deftest null-becomes-nil
  (let ((back (jvalue->lisp (parse-json "{\"publishedAt\": null, \"tags\": [null, \"a\"], \"n\": 0}"))))
    (ok (null (getf back :published-at)))
    (ok (equal (getf back :tags) '(nil "a")))
    (ok (eql (getf back :n) 0))))

(deftest round-trip
  (let* ((lisp '(:title "Hello" :published-at "2026-01-01T00:00:00Z" :tags ("a" "b")
                 :meta (:view-count 3 :draft nil)))
         (json (to-json (lisp->jvalue lisp)))
         (back (jvalue->lisp (parse-json json))))
    (ok (search "\"publishedAt\"" json))
    (ok (search "\"viewCount\"" json))
    (ok (search "[\"a\",\"b\"]" json))
    (ok (search "\"draft\":null" json) "NIL is null, not an empty array")
    (ok (search "\"empty\":[]" (to-json (lisp->jvalue '(:empty #())))) "#() is an empty array")
    (ok (search "\"nested\":[[1,2]]" (to-json (lisp->jvalue '(:nested ((1 2)))))) "lists inside vectors convert too")
    (ok (string= (getf back :title) "Hello"))
    (ok (equal (getf back :tags) '("a" "b")))
    (ok (= (getf (getf back :meta) :view-count) 3))
    (ok (null (getf (getf back :meta) :draft)))))
