(defpackage #:koya-core/data
  (:use #:cl)
  (:import-from #:access
                #:access)
  (:export #:array-p
           #:data-equal
           #:without-nulls))
(in-package #:koya-core/data)

(defun array-p (value)
  (and (vectorp value) (not (stringp value))))

(defun plist-equal (a b)
  (and (= (length a) (length b))
       (loop :for (key value) :on a :by #'cddr
             :always (multiple-value-bind (other found) (access b key :test #'eq)
                       (and found (data-equal value other))))))

(defun data-equal (a b)
  (cond ((and (listp a) (listp b)) (plist-equal a b))
        ((and (array-p a) (array-p b))
         (and (= (length a) (length b)) (every #'data-equal a b)))
        ((and (numberp a) (numberp b)) (= a b))
        (t (equal a b))))

(defun without-nulls (value)
  (cond ((consp value)
         (loop :for (key v) :on value :by #'cddr
               :unless (eq v :null) :append (list key (without-nulls v))))
        ((array-p value) (map 'vector #'without-nulls value))
        (t value)))
