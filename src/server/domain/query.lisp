(defpackage #:koya-server/domain/query
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:+system-fields+ #:model-fields #:field-name #:field-type #:field-fields)
  (:import-from #:koya-server/domain/errors
                #:invalid-input)
  (:import-from #:cl-ppcre
                #:scan-to-strings #:split)
  (:export #:query-error
           #:bad-query
           #:parse-query
           #:query #:make-query
           #:query-limit #:query-offset #:query-orders #:query-filters #:query-fields #:query-include
           #:query-search
           #:search-filters
           #:+system-fields+))
(in-package #:koya-server/domain/query)

(define-condition query-error (invalid-input) ()
  (:default-initargs :code "bad_query"))

(defun bad-query (fmt &rest args)
  (error 'query-error :message (apply #'format nil fmt args)))

(defparameter +default-limit+ 10)
(defparameter +max-limit+ 100)

(defstruct query
  (limit +default-limit+)
  (offset 0)
  orders
  filters
  fields
  include
  search)

(defun param (params name)
  (let ((v (cdr (assoc name params :test #'string=))))
    (and (stringp v) (string/= v "") v)))

(defun parse-integer-param (params name default &key (min 0) max)
  (let ((raw (param params name)))
    (if (null raw)
        default
        (let ((n (handler-case (parse-integer raw) (error () (bad-query "~a must be an integer" name)))))
          (when (< n min) (bad-query "~a must be at least ~a" name min))
          (cond ((and max (> n max)) max)
                ((typep n '(signed-byte 64)) n)
                (t (bad-query "~a is too large" name)))))))

(defun split-csv (string)
  (remove "" (mapcar (lambda (s) (string-trim " " s)) (split "," string)) :test #'string=))

(defun parse-include (string)
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
  (make-query :limit (parse-integer-param params "limit" +default-limit+ :min 0 :max +max-limit+)
              :offset (parse-integer-param params "offset" 0)
              :orders (let ((o (param params "orders"))) (and o (parse-orders o)))
              :filters (let ((f (param params "filters"))) (and f (parse-filters f)))
              :fields (let ((f (param params "fields"))) (and f (split-csv f)))
              :include (let ((i (param params "include"))) (and i (parse-include i)))
              :search (param params "q")))

(defparameter +searchable-types+ '(:text :textarea :slug :richtext))

(defun search-filters (model search-text)
  (let ((text-fields (loop :for field :in (model-fields model)
                           :when (member (field-type field) (cons :repeater +searchable-types+))
                             :collect (field-name field)
                           :when (eq (field-type field) :custom)
                             :append (loop :for inner :in (field-fields field)
                                           :when (member (field-type inner) +searchable-types+)
                                             :collect (format nil "~a.~a" (field-name field) (field-name inner))))))
    (cons (list (list "id" "equals" search-text))
          (mapcar (lambda (name) (list (list name "contains" search-text))) text-fields))))
