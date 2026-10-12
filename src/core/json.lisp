(defpackage #:koya-core/json
  (:use #:cl)
  (:import-from #:com.inuoe.jzon
                #:parse
                #:stringify
                #:json-parse-error)
  (:export #:parse-json
           #:json-parse-error
           #:to-json
           #:json-null
           #:json-null-p
           #:json-array
           #:jget
           #:jobject
           #:jkeys
           #:json-equal))
(in-package #:koya-core/json)

(defconstant json-null 'null)

(defun json-null-p (value) (eq value 'null))

(defun json-array (&rest values) (coerce values 'vector))

(defun parse-json (string)
  (parse string))

(defun to-json (value &key pretty)
  (stringify value :pretty pretty))

(defun jobject (&rest kv)
  (let ((out (make-hash-table :test 'equal)))
    (loop :for (k v) :on kv :by #'cddr
          :do (setf (gethash k out) v))
    out))

(defun jget (object &rest keys)
  (let ((current object))
    (loop :for (key . rest) :on keys
          :do (multiple-value-bind (v found) (if (hash-table-p current) (gethash key current) (values nil nil))
                (unless found (return-from jget (values nil nil)))
                (if rest (setf current v) (return-from jget (values v t)))))
    (values current t)))

(defun jkeys (object)
  (let ((keys '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k keys)) object)
    (sort keys #'string<)))
