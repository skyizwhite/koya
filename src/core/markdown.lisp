(defpackage #:koya/core/markdown
  (:use #:cl)
  (:import-from #:3bmd
                #:parse-string-and-print-to-stream)
  (:import-from #:3bmd-code-blocks
                #:*code-blocks*
                #:*renderer*
                #:render-code-block)
  (:import-from #:3bmd-tables
                #:*tables*)
  (:export #:render-markdown))
(in-package #:koya/core/markdown)

;;; Markdown -> HTML via 3bmd with GitHub-style tables and fenced code blocks.
;;; Fenced code is emitted as plain <pre><code class="language-X"> so that
;;; syntax highlighting, if wanted, happens on the consuming site.

(defun escape-html (string)
  (with-output-to-string (out)
    (loop :for c :across string
          :do (case c
                (#\< (write-string "&lt;" out))
                (#\> (write-string "&gt;" out))
                (#\& (write-string "&amp;" out))
                (#\" (write-string "&quot;" out))
                (t (write-char c out))))))

(defmethod render-code-block ((renderer (eql :plain)) stream lang params code)
  (declare (ignore params))
  (format stream "<pre><code~@[ class=\"language-~a\"~]>~a</code></pre>"
          (and lang (plusp (length lang)) (escape-html lang))
          (escape-html code)))

(defun render-markdown (markdown)
  "Convert a Markdown string to an HTML string."
  (let ((*code-blocks* t)
        (*tables* t)
        (*renderer* :plain))
    (with-output-to-string (out)
      (parse-string-and-print-to-stream markdown out))))
