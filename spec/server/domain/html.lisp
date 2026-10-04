(defpackage #:koya-spec/server/domain/html
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/html #:html-text))
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
  (ok (string= (html-text "日本語の<strong>本文</strong>") "日本語の本文"))
  (ok (string= (html-text "") "")))
