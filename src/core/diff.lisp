(defpackage #:koya/core/diff
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:schema-spaces #:space-name #:space-webhooks #:space-models
                #:model-name #:model-kind #:model-fields #:model-options
                #:field-name #:field-type #:field-options)
  (:import-from #:koya/core/json
                #:jobject)
  (:export #:diff-schemas
           #:destructive-change-p
           #:destructive-changes-p
           #:format-change
           #:change->jobject))
(in-package #:koya/core/diff)

;;; Structural diff between two schemas, used by plan/push. Each change is a
;;; plist: (:op OP :space S :model M :field F :from X :to Y).
;;; Destructive ops are the ones that can hide or invalidate existing content.

(defparameter *destructive-ops* '(:remove-space :remove-model :remove-field :change-kind :change-field-type))

(defun destructive-change-p (change)
  (and (member (getf change :op) *destructive-ops*) t))

(defun destructive-changes-p (changes)
  (some #'destructive-change-p changes))

(defun by-name (items key)
  (mapcar (lambda (item) (cons (funcall key item) item)) items))

(defun diff-named (old new key add-fn remove-fn both-fn)
  (let ((olds (by-name old key))
        (news (by-name new key))
        (changes '()))
    (loop :for (name . item) :in olds
          :unless (assoc name news :test #'string=)
            :do (setf changes (append changes (funcall remove-fn item))))
    (loop :for (name . item) :in news
          :for old-item = (cdr (assoc name olds :test #'string=))
          :do (setf changes (append changes (if old-item (funcall both-fn old-item item) (funcall add-fn item)))))
    changes))

(defun plist-equal (a b)
  (and (= (length a) (length b))
       (loop :for (k v) :on a :by #'cddr
             :always (equalp v (getf b k '%missing)))))

(defun diff-fields (space model old new)
  (diff-named
   old new #'field-name
   (lambda (f) (list (list :op :add-field :space space :model model :field (field-name f) :to (field-type f))))
   (lambda (f) (list (list :op :remove-field :space space :model model :field (field-name f) :from (field-type f))))
   (lambda (o n)
     (cond ((not (eq (field-type o) (field-type n)))
            (list (list :op :change-field-type :space space :model model :field (field-name n)
                        :from (field-type o) :to (field-type n))))
           ((not (plist-equal (field-options o) (field-options n)))
            (list (list :op :change-field-options :space space :model model :field (field-name n)
                        :from (field-options o) :to (field-options n))))
           (t nil)))))

(defun diff-models (space old new)
  (diff-named
   old new #'model-name
   (lambda (m) (cons (list :op :add-model :space space :model (model-name m) :to (model-kind m))
                     (diff-fields space (model-name m) nil (model-fields m))))
   (lambda (m) (list (list :op :remove-model :space space :model (model-name m))))
   (lambda (o n)
     (append (unless (eq (model-kind o) (model-kind n))
               (list (list :op :change-kind :space space :model (model-name n)
                           :from (model-kind o) :to (model-kind n))))
             (unless (plist-equal (model-options o) (model-options n))
               (list (list :op :change-model-options :space space :model (model-name n)
                           :from (model-options o) :to (model-options n))))
             (diff-fields space (model-name n) (model-fields o) (model-fields n))))))

(defun diff-spaces (old new)
  (diff-named
   old new #'space-name
   (lambda (s) (cons (list :op :add-space :space (space-name s))
                     (diff-models (space-name s) nil (space-models s))))
   (lambda (s) (list (list :op :remove-space :space (space-name s))))
   (lambda (o n)
     (append (unless (equal (space-webhooks o) (space-webhooks n))
               (list (list :op :change-webhooks :space (space-name n)
                           :from (space-webhooks o) :to (space-webhooks n))))
             (diff-models (space-name n) (space-models o) (space-models n))))))

(defun diff-schemas (old new)
  "List the changes needed to turn schema OLD into schema NEW."
  (diff-spaces (and old (schema-spaces old)) (schema-spaces new)))

(defun path (change)
  (format nil "~a~@[.~a~]~@[.~a~]" (getf change :space) (getf change :model) (getf change :field)))

(defun format-change (change)
  (let ((op (getf change :op)))
    (format nil "~:[ ~;!~] ~a ~a~@[ (~(~a~))~]~@[ ~a~]"
            (destructive-change-p change)
            (case op
              ((:add-space :add-model :add-field) "+")
              ((:remove-space :remove-model :remove-field) "-")
              (t "~"))
            (path change)
            (case op
              ((:add-model :add-field) (getf change :to))
              ((:remove-field) (getf change :from))
              (t nil))
            (case op
              ((:change-kind :change-field-type)
               (format nil "~(~a~) -> ~(~a~)" (getf change :from) (getf change :to)))
              ((:change-field-options :change-model-options) "options changed")
              (:change-webhooks "webhooks changed")
              (t nil)))))

(defun change->jobject (change)
  (jobject "op" (string-downcase (substitute #\_ #\- (symbol-name (getf change :op))))
           "path" (path change)
           "destructive" (destructive-change-p change)
           "description" (string-trim " " (format-change change))))
