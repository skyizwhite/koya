(defpackage #:koya/core/json
  (:use #:cl)
  (:import-from #:com.inuoe.jzon
                #:parse
                #:stringify)
  (:export #:parse-json
           #:to-json
           #:json-null
           #:json-null-p
           #:json-array
           #:json-array-p
           #:jget
           #:jset
           #:jobject
           #:jkeys
           #:json-equal))
(in-package #:koya/core/json)

;;; Thin layer over jzon. Objects are EQUAL hash tables with string keys,
;;; arrays are vectors, null is the symbol JSON-NULL (jzon's 'NULL), false is NIL
;;; and true is T.

(defconstant json-null 'null)

(defun json-null-p (value) (eq value 'null))

(defun json-array (&rest values) (coerce values 'vector))

(defun json-array-p (value) (and (vectorp value) (not (stringp value))))

(defun parse-json (string)
  (parse string))

(defun to-json (value &key pretty)
  (stringify value :pretty pretty))

(defun jobject (&rest kv)
  "Build a JSON object from alternating string keys and values."
  (let ((out (make-hash-table :test 'equal)))
    (loop :for (k v) :on kv :by #'cddr
          :do (setf (gethash k out) v))
    out))

(defun jget (object &rest keys)
  "Nested lookup. Returns two values like GETHASH; a missing intermediate returns NIL NIL."
  (let ((current object))
    (loop :for (key . rest) :on keys
          :do (multiple-value-bind (v found) (if (hash-table-p current) (gethash key current) (values nil nil))
                (unless found (return-from jget (values nil nil)))
                (if rest (setf current v) (return-from jget (values v t)))))
    (values current t)))

(defun jset (object key value)
  (setf (gethash key object) value)
  object)

(defun jkeys (object)
  (let ((keys '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k keys)) object)
    (sort keys #'string<)))

(defun json-equal (a b)
  "True when A and B are the same JSON value. Not EQUALP: that compares strings
without case, and \"Title\" and \"title\" are two values."
  (cond ((and (hash-table-p a) (hash-table-p b))
         (and (= (hash-table-count a) (hash-table-count b))
              (loop :for key :being :the :hash-keys :of a :using (:hash-value value)
                    :always (multiple-value-bind (other found) (gethash key b)
                              (and found (json-equal value other))))))
        ((and (json-array-p a) (json-array-p b))
         (and (= (length a) (length b)) (every #'json-equal a b)))
        ((and (numberp a) (numberp b)) (= a b))
        (t (equal a b))))
