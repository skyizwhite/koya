(defpackage #:koya-server/domain/query
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:+system-fields+)
  (:import-from #:koya-server/domain/errors
                #:invalid-input)
  (:import-from #:cl-ppcre
                #:scan-to-strings #:split)
  (:export #:query-error
           #:bad-query
           #:parse-query
           #:query #:make-query
           #:query-limit #:query-offset #:query-orders #:query-filters #:query-fields #:query-include
           #:+system-fields+))
(in-package #:koya-server/domain/query)

;;; The delivery API's list query: its parameters (docs/API.md) read into a
;;; QUERY. What a filter means against stored data is the store's to say.

(define-condition query-error (invalid-input) ()
  (:default-initargs :code "bad_query"))

(defun bad-query (fmt &rest args)
  (error 'query-error :message (apply #'format nil fmt args)))

(defparameter +default-limit+ 10)
(defparameter +max-limit+ 100)

(defstruct query
  (limit +default-limit+)  ; NIL for every row
  (offset 0)
  orders    ; list of (name . :asc/:desc)
  filters   ; list of groups, each group a list of (name op value); groups are OR'ed, terms AND'ed
  fields    ; list of field names or NIL for all
  include)  ; list of reference paths to embed, each a list of field names (a.b -> ("a" "b"))

(defun param (params name)
  (let ((v (cdr (assoc name params :test #'string=))))
    (if (and (stringp v) (string= v "")) nil v)))

(defun parse-integer-param (params name default &key (min 0) max)
  (let ((raw (param params name)))
    (if (null raw)
        default
        (let ((n (handler-case (parse-integer raw) (error () (bad-query "~a must be an integer" name)))))
          (when (< n min) (bad-query "~a must be at least ~a" name min))
          (if (and max (> n max)) max n)))))

(defun split-csv (string)
  (remove "" (mapcar (lambda (s) (string-trim " " s)) (split "," string)) :test #'string=))

(defun parse-include (string)
  "include=tags,author.avatar -> ((\"tags\") (\"author\" \"avatar\"))"
  (mapcar (lambda (path) (remove "" (split "\\." path) :test #'string=)) (split-csv string)))

(defun parse-orders (string)
  (mapcar (lambda (item)
            (if (char= (char item 0) #\-)
                (cons (subseq item 1) :desc)
                (cons item :asc)))
          (split-csv string)))

(defun parse-term (term)
  (multiple-value-bind (match groups) (scan-to-strings "^([A-Za-z0-9_.]+)\\[([a-z_]+)\\](.*)$" term)
    (unless match (bad-query "malformed filter ~s" term))
    (list (aref groups 0) (aref groups 1) (aref groups 2))))

(defun parse-filters (string)
  "\"a[equals]1[and]b[exists][or]c[equals]2\" -> ((\"a\" ... ) (\"b\" ...)) groups OR'ed."
  (let ((groups '())
        (current '())
        (rest string))
    (loop
      (multiple-value-bind (match parts) (scan-to-strings "^(.*?)\\[(and|or)\\](.*)$" rest)
        (cond (match
               (push (parse-term (aref parts 0)) current)
               (when (string= (aref parts 1) "or")
                 (push (nreverse current) groups)
                 (setf current '()))
               (setf rest (aref parts 2)))
              (t
               (push (parse-term rest) current)
               (push (nreverse current) groups)
               (return)))))
    (nreverse groups)))

(defun parse-query (params)
  "Build a QUERY from PARAMS, an alist of name and value strings. Signals
QUERY-ERROR on bad input."
  (make-query :limit (parse-integer-param params "limit" +default-limit+ :min 0 :max +max-limit+)
              :offset (parse-integer-param params "offset" 0)
              :orders (let ((o (param params "orders"))) (and o (parse-orders o)))
              :filters (let ((f (param params "filters"))) (and f (parse-filters f)))
              :fields (let ((f (param params "fields"))) (and f (split-csv f)))
              :include (let ((i (param params "include"))) (and i (parse-include i)))))
