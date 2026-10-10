(defpackage #:koya-core/case
  (:use #:cl)
  (:import-from #:koya-core/json #:json-array-p)
  (:import-from #:kebab
                #:to-camel-case
                #:to-kebab-case)
  (:export #:camel-key
           #:kebab-keyword
           #:plist->object
           #:object->plist
           #:jvalue->lisp
           #:lisp->jvalue))
(in-package #:koya-core/case)

(defun camel-key (key)
  (cond ((symbolp key) (to-camel-case (string-downcase (symbol-name key))))
        ((find #\- key) (to-camel-case key))
        (t key)))

(defun kebab-keyword (key)
  (intern (string-upcase (to-kebab-case (string key))) :keyword))

(defun lisp->jvalue (value)
  (cond ((null value) 'null)
        ((and (consp value) (keywordp (first value)))
         (plist->object value))
        ((listp value)
         (map 'vector #'lisp->jvalue value))
        ((json-array-p value)
         (map 'vector #'lisp->jvalue value))
        ((hash-table-p value)
         (let ((out (make-hash-table :test 'equal)))
           (maphash (lambda (k v) (setf (gethash (camel-key k) out) (lisp->jvalue v))) value)
           out))
        (t value)))

(defun jvalue->lisp (value)
  (cond ((eq value 'null) nil)
        ((hash-table-p value) (object->plist value))
        ((json-array-p value)
         (map 'list #'jvalue->lisp value))
        (t value)))

(defun plist->object (plist)
  (let ((out (make-hash-table :test 'equal)))
    (loop :for (k v) :on plist :by #'cddr
          :do (setf (gethash (camel-key k) out) (lisp->jvalue v)))
    out))

(defun object->plist (object)
  (let ((keys '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k keys)) object)
    (loop :for k :in (sort keys #'string<)
          :append (list (kebab-keyword k) (jvalue->lisp (gethash k object))))))
