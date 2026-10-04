(defpackage #:koya-server/domain/html
  (:use #:cl)
  (:import-from #:cl-ppcre #:split)
  (:export #:html-text
           #:data-text))
(in-package #:koya-server/domain/html)

(defparameter +block-tags+
  '("p" "br" "div" "li" "ul" "ol" "h1" "h2" "h3" "h4" "h5" "h6" "blockquote" "pre" "hr" "img"
    "table" "tr" "td" "th" "iframe" "video"))

(defparameter +entities+
  '(("amp" . #\&) ("lt" . #\<) ("gt" . #\>) ("quot" . #\") ("apos" . #\') ("nbsp" . #\Space)))

(defun tag-name (html start end)
  (let* ((from (if (and (< start end) (char= (char html start) #\/)) (1+ start) start))
         (to (or (position-if-not #'alphanumericp html :start from :end end) end)))
    (string-downcase (subseq html from to))))

(defun text-char (code)
  (and code (< 0 code char-code-limit)
       (not (<= #xD800 code #xDFFF))
       (not (<= #xFDD0 code #xFDEF))
       (/= (logand code #xFFFE) #xFFFE)
       (code-char code)))

(defun entity-char (name)
  (cond ((and (> (length name) 2) (char-equal (char name 1) #\x) (char= (char name 0) #\#))
         (text-char (parse-integer name :start 2 :radix 16 :junk-allowed t)))
        ((and (> (length name) 1) (char= (char name 0) #\#))
         (text-char (parse-integer name :start 1 :junk-allowed t)))
        (t (cdr (assoc name +entities+ :test #'string=)))))

(defun collapse-spaces (string)
  (let ((words (split "\\s+" string)))
    (format nil "~{~a~^ ~}" (remove "" words :test #'string=))))

(defun html-text (html)
  (let ((n (length html)) (i 0))
    (collapse-spaces
     (with-output-to-string (out)
       (loop :while (< i n)
             :do (let ((c (char html i)))
                   (cond ((char= c #\<)
                          (let ((close (position #\> html :start i)))
                            (cond ((null close) (write-string html out :start i) (setf i n))
                                  (t (when (member (tag-name html (1+ i) close) +block-tags+ :test #'string=)
                                       (write-char #\Space out))
                                     (setf i (1+ close))))))
                         ((char= c #\&)
                          (let* ((semi (position #\; html :start i :end (min n (+ i 12))))
                                 (decoded (and semi (entity-char (subseq html (1+ i) semi)))))
                            (cond (decoded (write-char decoded out) (setf i (1+ semi)))
                                  (t (write-char c out) (incf i)))))
                         (t (write-char c out) (incf i)))))))))

(defun data-text (data)
  (when data
    (let ((text (make-hash-table :test 'equal)))
      (maphash (lambda (name value)
                 (cond ((stringp value) (setf (gethash name text) (html-text value)))
                       ((hash-table-p value) (setf (gethash name text) (data-text value)))
                       ((and (vectorp value) (some #'hash-table-p value))
                        (setf (gethash name text)
                              (map 'vector (lambda (row) (if (hash-table-p row) (data-text row) row)) value)))))
               data)
      text)))
