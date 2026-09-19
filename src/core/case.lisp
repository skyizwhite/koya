(defpackage #:koya/core/case
  (:use #:cl)
  (:import-from #:kebab
                #:to-camel-case
                #:to-kebab-case)
  (:export #:camel-key
           #:kebab-keyword
           #:plist->object
           #:object->plist
           #:jvalue->lisp
           #:lisp->jvalue))
(in-package #:koya/core/case)

;;; Conversions between the wire representation (JSON objects with camelCase
;;; string keys, as jzon produces them: EQUAL hash tables and vectors) and the
;;; Lisp-friendly representation (plists with kebab-case keywords and lists).

(defun camel-key (key)
  "\"published-at\" / :published-at -> \"publishedAt\". Strings that are already
camelCase pass through unchanged."
  (cond ((symbolp key) (to-camel-case (string-downcase (symbol-name key))))
        ((find #\- key) (to-camel-case key))
        (t key)))

(defun kebab-keyword (key)
  "\"publishedAt\" -> :published-at."
  (intern (string-upcase (to-kebab-case (string key))) :keyword))

(defun lisp->jvalue (value)
  "Recursively convert a Lisp value into jzon's representation. Plists whose
first element is a keyword become objects, other lists become arrays."
  (cond ((and (consp value) (keywordp (first value)))
         (plist->object value))
        ((listp value)
         (map 'vector #'lisp->jvalue value))
        ((hash-table-p value)
         (let ((out (make-hash-table :test 'equal)))
           (maphash (lambda (k v) (setf (gethash (camel-key k) out) (lisp->jvalue v))) value)
           out))
        (t value)))

(defun jvalue->lisp (value)
  "Inverse of LISP->JVALUE. Objects become kebab-keyword plists, arrays become lists."
  (cond ((hash-table-p value) (object->plist value))
        ((and (vectorp value) (not (stringp value)))
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
