(defpackage #:koya-core/diff
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:schema-webhooks #:schema-models #:schema-custom-fields #:custom-field->jobject #:field-fields
                #:custom-field-name #:custom-field-fields
                #:model-name #:model-kind #:model-fields #:model-options #:model-was
                #:field-name #:field-type #:field-options #:field-was
                #:forget-rename)
  (:import-from #:koya-core/json
                #:jobject #:json-equal)
  (:import-from #:koya-core/case
                #:camel-key)
  (:export #:diff-schemas
           #:destructive-change-p
           #:destructive-changes-p
           #:tightened-change-p
           #:format-change
           #:change->jobject))
(in-package #:koya-core/diff)

(defparameter *destructive-ops* '(:remove-model :remove-field :change-kind :change-field-type))

(defun options-tightened-p (from to)
  (flet ((f (k) (getf from k)) (n (k) (getf to k)))
    (or (and (not (f :required)) (n :required))
        (and (not (f :unique)) (n :unique))
        (and (not (f :integer)) (n :integer))
        (not (eq (and (f :many) t) (and (n :many) t)))
        (and (n :max-length) (or (null (f :max-length)) (< (n :max-length) (f :max-length))))
        (and (n :pattern) (not (equal (n :pattern) (f :pattern))))
        (and (n :min) (or (null (f :min)) (> (n :min) (f :min))))
        (and (n :max) (or (null (f :max)) (< (n :max) (f :max))))
        (and (f :options) (set-difference (f :options) (n :options) :test #'equal) t)
        (and (f :custom-fields) (set-difference (f :custom-fields) (n :custom-fields) :test #'equal) t))))

(defun destructive-change-p (change)
  (and (member (getf change :op) *destructive-ops*) t))

(defun tightened-change-p (change)
  (and (eq (getf change :op) :change-field-options)
       (options-tightened-p (getf change :from) (getf change :to))))

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
             :always (equal v (getf b k '%missing)))))

(defun rename-pairs (old new key was)
  (loop :for item :in new
        :for was-name = (funcall was item)
        :for match = (and was-name
                          (null (find was-name new :key key :test #'string=))
                          (null (find (funcall key item) old :key key :test #'string=))
                          (find was-name old :key key :test #'string=))
        :when match :collect (cons match item)))

(defun without-renamed (items pairs pick)
  (remove-if (lambda (item) (find item pairs :key pick)) items))

(defun field-target (field)
  (case (field-type field)
    (:reference (getf (field-options field) :model))
    (:custom (getf (field-options field) :custom-field))))

(defun renamed-target (field renames)
  (let ((target (field-target field)))
    (if (eq (field-type field) :reference)
        (or (cdr (assoc target renames :test #'equal)) target)
        target)))

(defun inner-changes (model outer old new renames)
  (flet ((path (field) (format nil "~a.~a" outer (field-name field))))
    (diff-named
     old new #'field-name
     (lambda (f) (list (list :op :add-field :model model :field (path f) :to (field-type f))))
     (lambda (f) (list (list :op :remove-field :model model :field (path f) :from (field-type f))))
     (lambda (o n)
       (mapcar (lambda (change) (list* :op (getf change :op) :model model :field (path n) (nthcdr 6 change)))
               (field-changes model o n renames))))))

(defun field-changes (model old new renames)
  (let ((from (forget-rename (field-options old)))
        (to (forget-rename (field-options new))))
    (cond ((or (not (eq (field-type old) (field-type new)))
               (not (equal (renamed-target old renames) (field-target new))))
           (list (list :op :change-field-type :model model :field (field-name new)
                       :from (field-type old) :to (field-type new)
                       :from-target (field-target old) :to-target (field-target new))))
          (t
           (append (unless (plist-equal from to)
                     (list (list :op :change-field-options :model model :field (field-name new)
                                 :from from :to to)))
                   (case (field-type new)
                     (:custom
                      (inner-changes model (field-name new) (field-fields old) (field-fields new) renames))
                     (:repeater
                      (loop :for kind :in (field-fields new)
                            :for before := (find (custom-field-name kind) (field-fields old)
                                                 :key #'custom-field-name :test #'string=)
                            :when before
                              :append (inner-changes model (format nil "~a[~a]" (field-name new) (custom-field-name kind))
                                                     (custom-field-fields before) (custom-field-fields kind) renames)))))))))

(defun diff-fields (model old new renames)
  (let ((pairs (rename-pairs old new #'field-name #'field-was)))
    (append
     (loop :for (o . n) :in pairs
           :append (cons (list :op :rename-field :model model :field (field-name n) :from (field-name o))
                         (field-changes model o n renames)))
     (diff-named
      (without-renamed old pairs #'car) (without-renamed new pairs #'cdr) #'field-name
      (lambda (f) (list (list :op :add-field :model model :field (field-name f) :to (field-type f))))
      (lambda (f) (list (list :op :remove-field :model model :field (field-name f) :from (field-type f))))
      (lambda (o n) (field-changes model o n renames))))))

(defun model-changes (old new renames)
  (let ((from (forget-rename (model-options old)))
        (to (forget-rename (model-options new))))
    (append (unless (eq (model-kind old) (model-kind new))
              (list (list :op :change-kind :model (model-name new)
                          :from (model-kind old) :to (model-kind new))))
            (unless (plist-equal from to)
              (list (list :op :change-model-options :model (model-name new) :from from :to to)))
            (diff-fields (model-name new) (model-fields old) (model-fields new) renames))))

(defun diff-models (old new)
  (let* ((pairs (rename-pairs old new #'model-name #'model-was))
         (renames (mapcar (lambda (pair) (cons (model-name (car pair)) (model-name (cdr pair)))) pairs)))
    (append
     (loop :for (o . n) :in pairs
           :append (cons (list :op :rename-model :model (model-name n) :from (model-name o))
                         (model-changes o n renames)))
     (diff-named
      (without-renamed old pairs #'car) (without-renamed new pairs #'cdr) #'model-name
      (lambda (m) (cons (list :op :add-model :model (model-name m) :to (model-kind m))
                        (diff-fields (model-name m) nil (model-fields m) renames)))
      (lambda (m) (list (list :op :remove-model :model (model-name m))))
      (lambda (o n) (model-changes o n renames))))))

(defun custom-fields-equal (a b)
  (json-equal (map 'vector #'custom-field->jobject a) (map 'vector #'custom-field->jobject b)))

(defun diff-schemas (old new)
  (append (unless (equal (and old (schema-webhooks old)) (schema-webhooks new))
            (list (list :op :change-webhooks
                        :from (and old (schema-webhooks old)) :to (schema-webhooks new))))
          (unless (custom-fields-equal (and old (schema-custom-fields old)) (schema-custom-fields new))
            (list (list :op :change-custom-fields)))
          (diff-models (and old (schema-models old)) (schema-models new))))

(defparameter +absent+ '%missing)

(defun option-value (value)
  (cond ((eq value +absent+) "none")
        ((eq value t) "true")
        ((null value) "false")
        ((and (consp value) (every #'stringp value)) (format nil "~{~s~^, ~}" value))
        (t (princ-to-string value))))

(defun option-differences (from to)
  (let ((keys (sort (remove-duplicates
                     (append (loop :for (k nil) :on from :by #'cddr :collect k)
                             (loop :for (k nil) :on to :by #'cddr :collect k)))
                    #'string< :key #'camel-key)))
    (loop :for key :in keys
          :for was := (getf from key +absent+)
          :for now := (getf to key +absent+)
          :unless (equal was now)
            :collect (format nil "~a ~a -> ~a" (camel-key key) (option-value was) (option-value now)))))

(defun options-detail (change label)
  (let ((differences (option-differences (getf change :from) (getf change :to))))
    (if differences
        (format nil "~a (~{~a~^, ~})" label differences)
        label)))

(defun path (change)
  (format nil "~@[~a~]~@[.~a~]"
          (or (getf change :model) (if (eq (getf change :op) :change-custom-fields) "customFields" "webhooks"))
          (getf change :field)))

(defun misfit-note (change)
  (let ((ids (remove-duplicates (mapcar (lambda (m) (getf m :id)) (getf change :misfits)) :test #'equal)))
    (and ids (format nil "~a content~:p ~:*~[~;does~:;do~] not fit" (length ids)))))

(defun format-change (change)
  (let ((op (getf change :op)))
    (format nil "~:[ ~;!~] ~a ~a~@[ (~(~a~))~]~@[ ~a~]~@[, ~a~]"
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
              (:change-kind
               (format nil "~(~a~) -> ~(~a~), its contents are deleted" (getf change :from) (getf change :to)))
              (:change-field-type
               (format nil "~(~a~)~@[ to ~a~] -> ~(~a~)~@[ to ~a~]"
                       (getf change :from) (getf change :from-target)
                       (getf change :to) (getf change :to-target)))
              (:change-field-options
               (options-detail change (if (tightened-change-p change) "options tightened" "options changed")))
              (:change-model-options (options-detail change "options changed"))
              ((:change-webhooks :change-custom-fields) "changed")
              (t nil))
            (misfit-note change))))

(defun misfit->jobject (misfit)
  (jobject "id" (getf misfit :id)
           "field" (getf misfit :field)
           "version" (getf misfit :version)
           "message" (getf misfit :message)))

(defun change->jobject (change)
  (let ((object (jobject "op" (string-downcase (substitute #\_ #\- (symbol-name (getf change :op))))
                         "path" (path change)
                         "destructive" (destructive-change-p change)
                         "description" (string-trim " " (format-change change)))))
    (when (getf change :misfits)
      (setf (gethash "misfits" object) (map 'vector #'misfit->jobject (getf change :misfits))))
    object))
