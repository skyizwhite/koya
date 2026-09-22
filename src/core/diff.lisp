(defpackage #:koya/core/diff
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:schema-webhooks #:schema-models
                #:model-name #:model-kind #:model-fields #:model-options #:model-was
                #:field-name #:field-type #:field-options #:field-was
                #:forget-rename)
  (:import-from #:koya/core/json
                #:jobject)
  (:export #:diff-schemas
           #:destructive-change-p
           #:destructive-changes-p
           #:format-change
           #:change->jobject))
(in-package #:koya/core/diff)

;;; Structural diff between two schemas, used by plan/deploy. Both sides are one
;;; space's schema, so a change is a plist (:op OP :model M :field F :from X :to Y);
;;; the space is whichever one the deploy is addressed to.
;;; Destructive ops are the ones that can hide or invalidate existing content.
;;;
;;; A :WAS on a model or a field turns what would be a removal and an addition
;;; into a rename, which the deploy carries through to the stored content. It is
;;; matched here and nowhere else, and it never counts as a change of shape: two
;;; fields that differ only in :WAS are the same field.

(defparameter *destructive-ops* '(:remove-model :remove-field :change-kind :change-field-type))

(defun options-tightened-p (from to)
  "True when field options TO can reject content that FROM accepted: a constraint
was added or narrowed, or the single/many shape changed."
  (flet ((f (k) (getf from k)) (n (k) (getf to k)))
    (or (and (not (f :required)) (n :required))
        (and (not (f :unique)) (n :unique))
        (and (not (f :integer)) (n :integer))
        (not (eq (and (f :many) t) (and (n :many) t)))
        (and (n :max-length) (or (null (f :max-length)) (< (n :max-length) (f :max-length))))
        (and (n :pattern) (not (equal (n :pattern) (f :pattern))))
        (and (n :min) (or (null (f :min)) (> (n :min) (f :min))))
        (and (n :max) (or (null (f :max)) (< (n :max) (f :max))))
        (and (f :options) (set-difference (f :options) (n :options) :test #'equal) t))))

(defun destructive-change-p (change)
  (let ((op (getf change :op)))
    (or (and (member op *destructive-ops*) t)
        (and (eq op :change-field-options)
             (options-tightened-p (getf change :from) (getf change :to))))))

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
  "EQUAL, not EQUALP: a case-only change to a pattern or an option is a change."
  (and (= (length a) (length b))
       (loop :for (k v) :on a :by #'cddr
             :always (equal v (getf b k '%missing)))))

(defun rename-pairs (old new key was)
  "Pairs (OLD-ITEM . NEW-ITEM) where NEW-ITEM's :WAS names OLD-ITEM. A :WAS that
names nothing in OLD is not a rename: it is the annotation left in the source
after the rename was deployed. Neither is one whose new name OLD already uses,
or one NEW still declares -- the schema check refuses the latter, and the diff
does not lean on that."
  (loop :for item :in new
        :for was-name = (funcall was item)
        :for match = (and was-name
                          (null (find was-name new :key key :test #'string=))
                          (null (find (funcall key item) old :key key :test #'string=))
                          (find was-name old :key key :test #'string=))
        :when match :collect (cons match item)))

(defun without-renamed (items pairs pick)
  (remove-if (lambda (item) (find item pairs :key pick)) items))

(defun field-changes (model old new)
  "What changed between two versions of one field, whatever it is now called."
  (let ((from (forget-rename (field-options old)))
        (to (forget-rename (field-options new))))
    (cond ((not (eq (field-type old) (field-type new)))
           (list (list :op :change-field-type :model model :field (field-name new)
                       :from (field-type old) :to (field-type new))))
          ((not (plist-equal from to))
           (list (list :op :change-field-options :model model :field (field-name new)
                       :from from :to to)))
          (t nil))))

(defun diff-fields (model old new)
  (let ((pairs (rename-pairs old new #'field-name #'field-was)))
    (append
     (loop :for (o . n) :in pairs
           :append (cons (list :op :rename-field :model model :field (field-name n) :from (field-name o))
                         (field-changes model o n)))
     (diff-named
      (without-renamed old pairs #'car) (without-renamed new pairs #'cdr) #'field-name
      (lambda (f) (list (list :op :add-field :model model :field (field-name f) :to (field-type f))))
      (lambda (f) (list (list :op :remove-field :model model :field (field-name f) :from (field-type f))))
      (lambda (o n) (field-changes model o n))))))

(defun model-changes (old new)
  "What changed between two versions of one model, whatever it is now called."
  (let ((from (forget-rename (model-options old)))
        (to (forget-rename (model-options new))))
    (append (unless (eq (model-kind old) (model-kind new))
              (list (list :op :change-kind :model (model-name new)
                          :from (model-kind old) :to (model-kind new))))
            (unless (plist-equal from to)
              (list (list :op :change-model-options :model (model-name new) :from from :to to)))
            (diff-fields (model-name new) (model-fields old) (model-fields new)))))

(defun diff-models (old new)
  (let ((pairs (rename-pairs old new #'model-name #'model-was)))
    (append
     (loop :for (o . n) :in pairs
           :append (cons (list :op :rename-model :model (model-name n) :from (model-name o))
                         (model-changes o n)))
     (diff-named
      (without-renamed old pairs #'car) (without-renamed new pairs #'cdr) #'model-name
      (lambda (m) (cons (list :op :add-model :model (model-name m) :to (model-kind m))
                        (diff-fields (model-name m) nil (model-fields m))))
      (lambda (m) (list (list :op :remove-model :model (model-name m))))
      #'model-changes))))

(defun diff-schemas (old new)
  "List the changes needed to turn schema OLD into schema NEW. Both are the schema
of one space; OLD may be NIL, which is the same as an empty space."
  (append (unless (equal (and old (schema-webhooks old)) (schema-webhooks new))
            (list (list :op :change-webhooks
                        :from (and old (schema-webhooks old)) :to (schema-webhooks new))))
          (diff-models (and old (schema-models old)) (schema-models new))))

(defun path (change)
  (format nil "~@[~a~]~@[.~a~]" (or (getf change :model) "webhooks") (getf change :field)))

(defun format-change (change)
  (let ((op (getf change :op)))
    (format nil "~:[ ~;!~] ~a ~a~@[ (~(~a~))~]~@[ ~a~]"
            (destructive-change-p change)
            (case op
              ((:add-model :add-field) "+")
              ((:remove-model :remove-field) "-")
              (t "~"))
            (path change)
            (case op
              ((:add-model :add-field) (getf change :to))
              ((:remove-field) (getf change :from))
              (t nil))
            (case op
              ((:rename-model :rename-field)
               (format nil "renamed from ~a" (getf change :from)))
              ((:change-kind :change-field-type)
               (format nil "~(~a~) -> ~(~a~)" (getf change :from) (getf change :to)))
              (:change-field-options (if (destructive-change-p change) "options tightened" "options changed"))
              (:change-model-options "options changed")
              (:change-webhooks "changed")
              (t nil)))))

(defun change->jobject (change)
  (jobject "op" (string-downcase (substitute #\_ #\- (symbol-name (getf change :op))))
           "path" (path change)
           "destructive" (destructive-change-p change)
           "description" (string-trim " " (format-change change))))
