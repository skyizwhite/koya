(defpackage #:koya-core/case
  (:use #:cl)
  (:import-from #:koya-core/json #:json-array-p)
  (:export #:camel-key
           #:name-does-not-come-back
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

(define-condition name-does-not-come-back (error)
  ((name :initarg :name)
   (written :initarg :written)
   (read-back :initarg :read-back))
  (:report (lambda (c s)
             (with-slots (name written read-back) c
               (format s "~s does not come back as itself: it is written ~a and read back as :~(~a~)"
                       name written read-back)))))

(defun camel-key (key)
  (if (or (symbolp key) (find #\- key))
      (let* ((name (if (symbolp key) (symbol-name key) (string-upcase key)))
             (camel (to-camel-case (string-downcase name))))
        (unless (and (string= (kebab-name camel) name) (or (symbolp key) (string= (string-downcase name) key)))
          (error 'name-does-not-come-back :name key :written camel :read-back (kebab-name camel)))
        camel)
      key))

(defun round-trip-name (key)
  (let ((name (kebab-name key)))
    (and (string= (to-camel-case (string-downcase name)) key) name)))

(defun kebab-keyword (key)
  (intern (or (round-trip-name key)
              (error 'name-does-not-come-back :name key :written (to-camel-case (string-downcase (kebab-name key)))
                                              :read-back (kebab-name key)))
          :keyword))

(defun find-kebab-keyword (key)
  (let ((name (round-trip-name key)))
    (and name (values (find-symbol name :keyword)))))

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
         (let ((out (make-hash-table :test 'equal)))
           (loop :for rest :on value :by #'cddr
                 :do (unless (and (keywordp (first rest)) (rest rest))
                       (error "~s is not a plist of data" value))
                     (setf (gethash (camel-key (first rest)) out) (data->jvalue (second rest))))
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
          :append (list (intern (or (round-trip-name k) (string-upcase k)) :keyword)
                        (jvalue->lisp (gethash k object))))))
