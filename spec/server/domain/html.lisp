(defpackage #:koya-spec/server/domain/html
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/html #:html-text #:data-text)
  (:import-from #:koya-core/json #:parse-json #:jget))
(in-package #:koya-spec/server/domain/html)

(deftest the-text-of-rich-text
  (ok (string= (html-text "<p>Hello <strong>bold</strong> world</p>") "Hello bold world") "tags go, the words stay")
  (ok (string= (html-text "<p>pro<em>gram</em>ming</p>") "programming") "an inline tag does not split a word")
  (ok (string= (html-text "<p>one</p><p>two</p>") "one two") "a block ends a word")
  (ok (string= (html-text "<p>line<br>break</p>") "line break"))
  (ok (string= (html-text "<a href=\"https://lisp.example/strong\" class=\"x\">link</a>") "link") "attributes are not text")
  (ok (string= (html-text "AT&amp;T &lt;tag&gt; &quot;q&quot; &#39;s&#x41;&#66;&nbsp;x") "AT&T <tag> \"q\" 'sAB x")
      "character references are what they stand for")
  (ok (string= (html-text "&bogus; & alone") "&bogus; & alone") "an unknown reference is left as it is")
  (ok (string= (html-text "a&#xD800;b&#xFFFF;c&#0;d") "a&#xD800;b&#xFFFF;c&#0;d")
      "and so is one that names no character text can hold")
  (ok (string= (html-text "日本語の<strong>本文</strong>") "日本語の本文"))
  (ok (string= (html-text "") "")))

(deftest the-text-of-a-contents-data
  (let ((text (data-text (parse-json "{\"title\":\"A &amp; B\",\"body\":\"<p>one</p><p>two</p>\",\"count\":3,\"tags\":[\"x\"],\"done\":true}"))))
    (ok (string= (jget text "body") "one two") "each string, as its text")
    (ok (string= (jget text "title") "A & B") "whatever its field's type")
    (ng (nth-value 1 (gethash "count" text)) "and nothing that is not a string")
    (ng (nth-value 1 (gethash "tags" text)))
    (ng (nth-value 1 (gethash "done" text))))
  (ok (= (hash-table-count (data-text (parse-json "{\"count\":3}"))) 0) "data without strings has an empty text, not none")
  (ok (null (data-text nil)) "no data, no text"))
