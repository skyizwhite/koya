(defpackage #:koya-tests/core/markdown
  (:use #:cl #:rove)
  (:import-from #:koya/core/markdown
                #:render-markdown))
(in-package #:koya-tests/core/markdown)

(deftest basics
  (ok (search "<h1>Title</h1>" (render-markdown "# Title")))
  (ok (search "<strong>bold</strong>" (render-markdown "**bold**")))
  (let ((html (render-markdown "[x](https://x)")))
    (ok (search "<a href=\"https://x\"" html))
    (ok (search ">x</a>" html))))

(deftest tables
  (ok (search "<table" (render-markdown "| a | b |
|---|---|
| 1 | 2 |"))))

(deftest code-blocks
  (let ((html (render-markdown "```lisp
(< 1 2)
```")))
    (ok (search "<pre><code class=\"language-lisp\">" html))
    (ok (search "(&lt; 1 2)" html) "escaped, not highlighted")
    (ng (search "<span" html)))
  (ok (search "<pre><code>plain</code></pre>" (render-markdown "```
plain
```"))))
