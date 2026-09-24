(defpackage #:koya-server/lib/paging
  (:use #:cl)
  (:import-from #:koya-server/lib/http
                #:param)
  (:export #:+page-size+
           #:page-number
           #:last-page
           #:page-offset))
(in-package #:koya-server/lib/paging)

;;; The pages of every list in the admin UI.

(defparameter +page-size+ 20
  "Rows per page, the same everywhere in the admin UI: a page is what fits on a
screen without scrolling past it, and the search and the filters are how a
particular row is found.")

(defun page-number (params)
  "?page=, or 1 for none or anything that is not a number."
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

(defun last-page (total &optional (size +page-size+))
  "The last page for TOTAL rows: 1 when there are none, so an empty list is a page."
  (max 1 (ceiling total size)))

(defun page-offset (page &optional (size +page-size+))
  (* (1- page) size))
