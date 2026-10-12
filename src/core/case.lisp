(defpackage #:koya-core/case
  (:use #:cl)
  (:import-from #:koya-core/json #:json-array-p)
  (:export #:camel-key
           #:kebab-keyword
           #:find-kebab-keyword
           #:jvalue->data
           #:data->jvalue
           #:plist->object
           #:object->plist
           #:jvalue->lisp
           #:lisp->jvalue))
(in-package #:koya-core/case)

(defun to-camel-case (kebab)
  (with-output-to-string (out)
    (loop :with up := nil
          :for char :across kebab
          :do (cond ((char= char #\-) (setf up t))
                    (up (write-char (char-upcase char) out) (setf up nil))
                    (t (write-char char out))))))

(defun kebab-name (camel)
  (with-output-to-string (out)
    (loop :for char :across camel
          :do (when (upper-case-p char) (write-char #\- out))
              (write-char (char-upcase char) out))))

(defun camel-key (key)
  (cond ((symbolp key) (to-camel-case (string-downcase (symbol-name key))))
        ((find #\- key) (to-camel-case key))
        (t key)))

(defun kebab-keyword (key)
  (intern (kebab-name key) :keyword))

(defun find-kebab-keyword (key)
  (let ((keyword (find-symbol (kebab-name key) :keyword)))
    (and keyword (string= (camel-key keyword) key) keyword)))

(defun jvalue->data (value &key intern)
  (cond ((eq value 'null) :null)
        ((hash-table-p value)
         (loop :for k :being :the :hash-keys :of value :using (:hash-value v)
               :append (list (if intern (kebab-keyword k) (or (find-kebab-keyword k) k))
                             (jvalue->data v :intern intern))))
        ((json-array-p value) (map 'vector (lambda (v) (jvalue->data v :intern intern)) value))
        (t value)))

(defun data->jvalue (value)
  (cond ((eq value :null) 'null)
        ((consp value)
         (unless (and (evenp (length value))
                      (loop :for k :in value :by #'cddr :always (keywordp k)))
           (error "~s is not a plist of data" value))
         (let ((out (make-hash-table :test 'equal)))
           (loop :for (k v) :on value :by #'cddr
                 :do (setf (gethash (camel-key k) out) (data->jvalue v)))
           out))
        ((json-array-p value) (map 'vector #'data->jvalue value))
        (t value)))

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
