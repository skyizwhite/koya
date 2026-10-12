(defpackage #:koya-core/case
  (:use #:cl)
  (:import-from #:koya-core/data #:array-p)
  (:export #:camel-key
           #:name-does-not-come-back
           #:kebab-keyword
           #:find-kebab-keyword
           #:jvalue->data
           #:data->jvalue
           #:data->jobject
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

(define-condition name-does-not-come-back (error)
  ((name :initarg :name)
   (becomes :initarg :becomes)
   (comes-back-as :initarg :comes-back-as))
  (:report (lambda (c s)
             (with-slots (name becomes comes-back-as) c
               (let ((*print-case* :downcase)
                     (*print-gensym* nil))
                 (flet ((shown (x) (if (stringp x) (prin1-to-string x) (format nil ":~s" x))))
                   (format s "~s does not come back as itself: it becomes ~a, which comes back as ~a"
                           name (shown becomes) (shown comes-back-as))))))))

(defun camel-key (key)
  (if (or (symbolp key) (find #\- key))
      (let* ((name (if (symbolp key) (symbol-name key) (string-upcase key)))
             (camel (to-camel-case (string-downcase name))))
        (unless (and (string= (kebab-name camel) name) (or (symbolp key) (notany #'upper-case-p key)))
          (error 'name-does-not-come-back :name key :becomes camel :comes-back-as (make-symbol (kebab-name camel))))
        camel)
      key))

(defun kebab-round-trip (key)
  (let* ((name (kebab-name key))
         (camel (to-camel-case (string-downcase name))))
    (values (and (string= camel key) name) name camel)))

(defun kebab-keyword (key)
  (multiple-value-bind (name kebab camel) (kebab-round-trip key)
    (unless name
      (error 'name-does-not-come-back :name key :becomes (make-symbol kebab) :comes-back-as camel))
    (intern name :keyword)))

(defun find-kebab-keyword (key)
  (let ((name (kebab-round-trip key)))
    (and name (values (find-symbol name :keyword)))))

(defun jvalue->data (value &key intern)
  (cond ((eq value 'null) :null)
        ((hash-table-p value)
         (loop :for k :being :the :hash-keys :of value :using (:hash-value v)
               :append (list (if intern (kebab-keyword k) (or (find-kebab-keyword k) k))
                             (jvalue->data v :intern intern))))
        ((array-p value) (map 'vector (lambda (v) (jvalue->data v :intern intern)) value))
        (t value)))

(defun data->jvalue (value)
  (cond ((eq value :null) 'null)
        ((consp value)
         (let ((out (make-hash-table :test 'equal)))
           (loop :for rest :on value :by #'cddr
                 :do (unless (and (keywordp (first rest)) (rest rest))
                       (error "~s is not a plist of data" value))
                     (setf (gethash (camel-key (first rest)) out) (data->jvalue (second rest))))
           out))
        ((array-p value) (map 'vector #'data->jvalue value))
        (t value)))

(defun data->jobject (data)
  (if data (data->jvalue data) (make-hash-table :test 'equal)))

(defun lisp->jvalue (value)
  (cond ((null value) 'null)
        ((and (consp value) (keywordp (first value)))
         (plist->object value))
        ((listp value)
         (map 'vector #'lisp->jvalue value))
        ((array-p value)
         (map 'vector #'lisp->jvalue value))
        ((hash-table-p value)
         (let ((out (make-hash-table :test 'equal)))
           (maphash (lambda (k v) (setf (gethash (camel-key k) out) (lisp->jvalue v))) value)
           out))
        (t value)))

(defun jvalue->lisp (value)
  (cond ((eq value 'null) nil)
        ((hash-table-p value) (object->plist value))
        ((array-p value)
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
