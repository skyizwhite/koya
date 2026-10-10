(defpackage #:koya-core/schema
  (:use #:cl)
  (:import-from #:koya-core/case
                #:camel-key)
  (:import-from #:koya-core/json
                #:jobject
                #:jget
                #:jkeys
                #:json-array-p
                #:json-null-p)
  (:import-from #:cl-ppcre
                #:scan #:create-scanner)
  (:export #:+schema-version+
           #:+system-fields+
           #:*field-types*
           #:field-type-p
           #:field-type-options
           #:field
           #:make-field
           #:field-name
           #:field-type
           #:field-options
           #:field-option
           #:field-fields
           #:field-row-kinds
           #:field-path-parts
           #:row-kind
           #:custom-field
           #:make-custom-field
           #:custom-field-name
           #:custom-field-fields
           #:custom-field->jobject
           #:jobject->custom-field
           #:schema-custom-fields
           #:schema-custom-field
           #:field-required-p
           #:field-many-p
           #:field-was
           #:forget-rename
           #:field-forget-rename
           #:model
           #:make-model
           #:model-name
           #:model-kind
           #:model-fields
           #:model-field
           #:model-options
           #:model-was
           #:model-forget-renames
           #:make-webhook
           #:webhook-label
           #:webhook-url
           #:webhook-only
           #:webhook-covers-p
           #:webhook->jobject
           #:jobject->webhook
           #:model-preview-url
           #:model-public-url
           #:model-label
           #:schema
           #:make-schema
           #:schema-webhooks
           #:schema-models
           #:schema-model
           #:schema-error
           #:schema-error-message
           #:schema-errors
           #:check-schema
           #:check-deployable
           #:schema->jobject
           #:jobject->schema
           #:field->jobject
           #:model->jobject
           #:jobject->model
           #:slug-name-p
           #:field-name-p))
(in-package #:koya-core/schema)

(defparameter +schema-version+ 1)

(defparameter +system-fields+ '("id" "createdAt" "updatedAt" "publishedAt" "revisedAt"))

(defparameter *field-types*
  '((:text      :required :max-length :pattern :unique)
    (:textarea  :required :max-length)
    (:richtext  :required)
    (:number    :required :min :max :integer)
    (:boolean   :required :default)
    (:date      :required)
    (:datetime  :required)
    (:select    :required :options :many)
    (:media     :required :many)
    (:reference :required :model :many)
    (:slug      :required :from :unique :pattern)
    (:custom    :required :custom-field)
    (:repeater  :required :custom-fields)))

(defparameter *universal-options* '(:was :help))

(defun field-type-p (type)
  (and (assoc type *field-types*) t))

(defun field-type-options (type)
  (append (rest (assoc type *field-types*)) *universal-options*))

(define-condition schema-error (error)
  ((message :initarg :message :reader schema-error-message))
  (:report (lambda (c s) (format s "Invalid schema: ~a" (schema-error-message c)))))

(defun fail (fmt &rest args)
  (error 'schema-error :message (apply #'format nil fmt args)))

(defun slug-name-p (string)
  (and (stringp string) (scan "^[a-z][a-z0-9-]*\\z" string) t))

(defun field-name-p (string)
  (and (stringp string) (scan "^[a-z][a-zA-Z0-9]*\\z" string) t))

(defstruct (field (:constructor %make-field))
  name
  type
  options
  fields)

(defun normalize-option (key value)
  (flet ((name-string (v) (if (symbolp v) (string-downcase (symbol-name v)) v)))
    (case key
      (:model (name-string value))
      ((:from :was :custom-field) (if (and value (symbolp value) (not (json-null-p value))) (camel-key value) value))
      (:options (if (or (listp value) (json-array-p value))
                    (map 'list #'name-string value)
                    value))
      (:custom-fields (if (or (listp value) (json-array-p value))
                          (map 'list (lambda (v) (if (and v (symbolp v)) (camel-key v) v)) value)
                          value))
      (t value))))

(defun check-option-value (field-name key value)
  (flet ((bad (what) (fail "field ~s: option ~s must be ~a, got ~s" field-name key what value)))
    (case key
      ((:required :unique :integer :many :default)
       (unless (member value '(t nil)) (bad "true or false")))
      (:max-length
       (unless (and (integerp value) (plusp value)) (bad "a positive integer")))
      ((:min :max)
       (unless (realp value) (bad "a number")))
      (:pattern
       (unless (stringp value) (bad "a string"))
       (handler-case (create-scanner value)
         (error () (fail "field ~s: :pattern ~s is not a valid regular expression" field-name value))))
      (:options
       (unless (and (consp value) (every #'stringp value)) (bad "a non-empty list of strings"))
       (when (/= (length value) (length (remove-duplicates value :test #'string=)))
         (bad "a list without duplicates")))
      (:model
       (unless (slug-name-p value) (bad "a model name")))
      ((:from :custom-field)
       (unless (field-name-p value) (bad "a field name")))
      (:custom-fields
       (unless (and (consp value) (every #'field-name-p value)) (bad "a non-empty list of custom field names"))
       (when (/= (length value) (length (remove-duplicates value :test #'string=)))
         (bad "a list without duplicates")))
      (:help
       (unless (and (stringp value) (plusp (length value))) (bad "a non-empty string")))
      (:was
       (unless (field-name-p value) (bad "a field name"))
       (when (member value +system-fields+ :test #'string=)
         (fail "field ~s: :was names the system field ~s" field-name value))))))

(defun make-field (name type &rest options)
  (let ((name (if (stringp name) name (camel-key name)))
        (options (loop :for (k v) :on options :by #'cddr
                       :unless (and (eq k :was) (null v))
                         :append (list k (normalize-option k v)))))
    (unless (field-name-p name)
      (fail "field name ~s must be a camelCase identifier" name))
    (when (member name +system-fields+ :test #'string=)
      (fail "field name ~s is reserved for a system field" name))
    (unless (field-type-p type)
      (fail "unknown field type ~s for field ~s" type name))
    (loop :for (k v) :on options :by #'cddr
          :unless (member k (field-type-options type))
            :do (fail "option ~s is not allowed on ~a field ~s" k type name)
          :do (check-option-value name k v))
    (when (and (eq type :select) (null (getf options :options)))
      (fail "select field ~s needs :options" name))
    (when (and (eq type :reference) (null (getf options :model)))
      (fail "reference field ~s needs :model" name))
    (when (and (eq type :slug) (null (getf options :from)))
      (fail "slug field ~s needs :from" name))
    (when (and (eq type :custom) (null (getf options :custom-field)))
      (fail "custom field ~s needs :custom-field" name))
    (when (and (eq type :repeater) (null (getf options :custom-fields)))
      (fail "repeater ~s needs :custom-fields" name))
    (when (equal (getf options :was) name)
      (fail "field ~s: :was must name the field it was renamed from, not itself" name))
    (%make-field :name name :type type :options options)))

(defun field-option (field key &optional default)
  (getf (field-options field) key default))

(defun field-was (field)
  (field-option field :was))

(defun forget-rename (options)
  (loop :for (key value) :on options :by #'cddr
        :unless (eq key :was) :append (list key value)))

(defun field-forget-rename (field)
  (if (field-was field)
      (%make-field :name (field-name field) :type (field-type field)
                   :options (forget-rename (field-options field))
                   :fields (field-fields field))
      field))

(defstruct (custom-field (:constructor %make-custom-field))
  name
  fields)

(defun make-custom-field (name fields)
  (let ((name (if (stringp name) name (camel-key name))))
    (unless (field-name-p name)
      (fail "custom field name ~s must be a camelCase identifier" name))
    (when (null fields)
      (fail "custom field ~s has no fields" name))
    (let ((names (mapcar #'field-name fields)))
      (when (/= (length names) (length (remove-duplicates names :test #'string=)))
        (fail "custom field ~s has duplicate field names" name)))
    (dolist (field fields)
      (when (string= (field-name field) "fieldId")
        (fail "custom field ~s: fieldId names a row's custom field and cannot be a field" name))
      (when (member (field-type field) '(:slug :custom :repeater))
        (fail "custom field ~s: a ~(~a~) field cannot be inside a custom field" name (field-type field)))
      (when (field-option field :unique)
        (fail "custom field ~s: field ~s cannot be unique inside a custom field" name (field-name field)))
      (when (field-was field)
        (fail "custom field ~s: field ~s cannot be renamed with :was inside a custom field" name (field-name field))))
    (%make-custom-field :name name :fields fields)))

(defun field-row-kinds (field) (field-fields field))

(defun row-kind (field row)
  (and (hash-table-p row)
       (find (gethash "fieldId" row) (field-fields field) :key #'custom-field-name :test #'equal)))

(defun field-path-parts (path)
  (let* ((bracket (position #\[ path))
         (dot (position #\. path))
         (end (or bracket dot)))
    (if (null end)
        (values path nil nil)
        (values (subseq path 0 end)
                (and bracket (subseq path (1+ bracket) (position #\] path)))
                (and dot (subseq path (1+ dot)))))))

(defun field-required-p (field) (and (field-option field :required) t))
(defun field-many-p (field) (and (field-option field :many) t))

(defun webhook-label (webhook) (getf webhook :label))
(defun webhook-url (webhook) (getf webhook :url))
(defun webhook-only (webhook)
  (getf webhook :only))

(defun webhook-covers-p (webhook model-name)
  (let ((only (webhook-only webhook)))
    (or (null only) (and (member model-name only :test #'string=) t))))

(defun normalize-only (label only)
  (let ((names (cond ((null only) '())
                     ((or (symbolp only) (stringp only)) (list only))
                     ((or (listp only) (json-array-p only)) (coerce only 'list))
                     (t (fail "webhook ~s: :only must be a model name or a list of them, got ~s" label only)))))
    (let ((names (mapcar (lambda (n)
                           (let ((n (if (symbolp n) (string-downcase (symbol-name n)) n)))
                             (unless (slug-name-p n)
                               (fail "webhook ~s: :only must name models, got ~s" label n))
                             n))
                         names)))
      (when (/= (length names) (length (remove-duplicates names :test #'string=)))
        (fail "webhook ~s: :only names the same model twice" label))
      names)))

(defun web-url-p (url)
  (or (and (> (length url) 7) (string-equal "http://" url :end2 7))
      (and (> (length url) 8) (string-equal "https://" url :end2 8))))

(defun make-webhook (label url &key only)
  (unless (and (stringp label) (plusp (length label))) (fail "webhook label must be a non-empty string, got ~s" label))
  (unless (and (stringp url) (plusp (length url))) (fail "webhook ~s: url must be a non-empty string, got ~s" label url))
  (unless (web-url-p url) (fail "webhook ~s: url ~s must start with http:// or https://" label url))
  (let ((only (normalize-only label only)))
    (append (list :label label :url url) (and only (list :only only)))))

(defun normalize-webhook (entry)
  (cond ((and (consp entry) (keywordp (first entry)))
         (make-webhook (getf entry :label) (getf entry :url) :only (getf entry :only)))
        ((hash-table-p entry) (jobject->webhook entry))
        (t (fail "a webhook must be (webhook label url), got ~s" entry))))

(defun normalize-webhooks (webhooks where)
  (unless (or (listp webhooks) (json-array-p webhooks))
    (fail "~a: :webhooks must be a list, got ~s" where webhooks))
  (let ((hooks (map 'list #'normalize-webhook webhooks)))
    (let ((labels (mapcar #'webhook-label hooks)))
      (when (/= (length labels) (length (remove-duplicates labels :test #'string=)))
        (fail "~a: webhook labels must be unique" where)))
    hooks))

(defstruct (model (:constructor %make-model))
  name
  kind
  fields
  options)

(defun check-field-renames (model-name fields)
  (let ((names (mapcar #'field-name fields))
        (renames (remove nil (mapcar #'field-was fields))))
    (when (/= (length renames) (length (remove-duplicates renames :test #'string=)))
      (fail "model ~s: two fields are renamed from the same field" model-name))
    (dolist (was renames)
      (when (member was names :test #'string=)
        (fail "model ~s: a field is renamed from ~s, which the model still declares" model-name was)))))

(defun name-designator (value)
  (cond ((json-null-p value) value)
        ((stringp value) (string-downcase value))
        ((and value (symbolp value)) (string-downcase (symbol-name value)))
        (t value)))

(defun make-model (name kind fields &key preview-url public-url label was)
  (let ((name (string-downcase (string name)))
        (was (name-designator was))
        (label (if (and label (symbolp label) (not (json-null-p label))) (camel-key label) label)))
    (dolist (url (list preview-url public-url))
      (unless (or (null url) (stringp url))
        (fail "model ~s: URL templates must be strings" name))
      (unless (or (null url) (web-url-p url))
        (fail "model ~s: URL template ~s must start with http:// or https://" name url)))
    (unless (or (null label) (stringp label))
      (fail "model ~s: :label must name a field" name))
    (unless (slug-name-p name)
      (fail "model name ~s must be lowercase letters, digits and hyphens" name))
    (when was
      (unless (slug-name-p was)
        (fail "model ~s: :was ~s must be a model name" name was))
      (when (string= was name)
        (fail "model ~s: :was must name the model it was renamed from, not itself" name)))
    (unless (member kind '(:list :object))
      (fail "model ~s: kind must be :list or :object, got ~s" name kind))
    (let ((names (mapcar #'field-name fields)))
      (when (/= (length names) (length (remove-duplicates names :test #'string=)))
        (fail "model ~s has duplicate field names" name)))
    (check-field-renames name fields)
    (%make-model :name name :kind kind :fields fields
                 :options (append (and preview-url (list :preview-url preview-url))
                                  (and public-url (list :public-url public-url))
                                  (and label (list :label label))
                                  (and was (list :was was))))))

(defun model-preview-url (model) (getf (model-options model) :preview-url))
(defun model-public-url (model) (getf (model-options model) :public-url))

(defun model-label (model)
  (getf (model-options model) :label))

(defun model-was (model)
  (getf (model-options model) :was))

(defun model-forget-renames (model)
  (%make-model :name (model-name model) :kind (model-kind model)
               :fields (mapcar #'field-forget-rename (model-fields model))
               :options (forget-rename (model-options model))))

(defun model-field (model name)
  (find (if (stringp name) name (camel-key name)) (model-fields model)
        :key #'field-name :test #'string=))

(defstruct (schema (:constructor %make-schema))
  webhooks
  custom-fields
  models)

(defun resolve-custom-fields (model custom-fields)
  (flet ((named (name) (find name custom-fields :key #'custom-field-name :test #'string=)))
    (flet ((resolve (field)
             (case (field-type field)
               (:custom
                (let ((custom (named (field-option field :custom-field))))
                  (%make-field :name (field-name field) :type :custom :options (field-options field)
                               :fields (and custom (custom-field-fields custom)))))
               (:repeater
                (%make-field :name (field-name field) :type :repeater :options (field-options field)
                             :fields (remove nil (mapcar #'named (field-option field :custom-fields)))))
               (t field))))
      (%make-model :name (model-name model) :kind (model-kind model)
                   :fields (mapcar #'resolve (model-fields model))
                   :options (model-options model)))))

(defun make-schema (&key webhooks custom-fields models)
  (let ((names (mapcar #'model-name models)))
    (when (/= (length names) (length (remove-duplicates names :test #'string=)))
      (fail "duplicate model names")))
  (let ((names (mapcar #'custom-field-name custom-fields)))
    (when (/= (length names) (length (remove-duplicates names :test #'string=)))
      (fail "duplicate custom field names")))
  (%make-schema :webhooks (normalize-webhooks webhooks "schema")
                :custom-fields custom-fields
                :models (mapcar (lambda (model) (resolve-custom-fields model custom-fields)) models)))

(defun schema-custom-field (schema name)
  (find name (schema-custom-fields schema) :key #'custom-field-name :test #'string=))

(defun schema-model (schema name)
  (find (string-downcase (string name)) (schema-models schema) :key #'model-name :test #'string=))

(defun schema-errors (schema)
  (let ((errors '()))
    (let ((renames (remove nil (mapcar #'model-was (schema-models schema)))))
      (dolist (was (remove-duplicates renames :test #'string= :from-end t))
        (when (> (count was renames :test #'string=) 1)
          (push (format nil "two models are renamed from ~s; only one of them can have its contents" was)
                errors))))
    (dolist (model (schema-models schema))
      (let ((was (model-was model)))
        (when (and was (schema-model schema was))
          (push (format nil "model ~a is renamed from ~s, which the schema still declares"
                        (model-name model) was)
                errors))))
    (dolist (hook (schema-webhooks schema))
      (dolist (name (webhook-only hook))
        (unless (schema-model schema name)
          (push (format nil "webhook ~s: :only names unknown model ~s" (webhook-label hook) name)
                errors))))
    (dolist (model (schema-models schema))
      (dolist (field (model-fields model))
        (case (field-type field)
          (:reference
           (let ((target (field-option field :model)))
             (unless (schema-model schema target)
               (push (format nil "~a.~a references unknown model ~s"
                             (model-name model) (field-name field) target)
                     errors))))
          (:custom
           (let ((name (field-option field :custom-field)))
             (unless (schema-custom-field schema name)
               (push (format nil "~a.~a: :customField names unknown custom field ~s"
                             (model-name model) (field-name field) name)
                     errors))))
          (:repeater
           (dolist (name (field-option field :custom-fields))
             (unless (schema-custom-field schema name)
               (push (format nil "~a.~a: :customFields names unknown custom field ~s"
                             (model-name model) (field-name field) name)
                     errors))))
          (:slug
           (let* ((from (field-option field :from))
                  (source (model-field model from)))
             (cond ((null source)
                    (push (format nil "~a.~a: :from refers to unknown field ~s"
                                  (model-name model) (field-name field) from)
                          errors))
                   ((or (eq source field) (not (member (field-type source) '(:text :textarea))))
                    (push (format nil "~a.~a: :from must name a text or textarea field other than itself"
                                  (model-name model) (field-name field))
                          errors))))))))
    (dolist (custom (schema-custom-fields schema))
      (dolist (field (custom-field-fields custom))
        (when (eq (field-type field) :reference)
          (let ((target (field-option field :model)))
            (unless (schema-model schema target)
              (push (format nil "custom field ~a.~a references unknown model ~s"
                            (custom-field-name custom) (field-name field) target)
                    errors))))))
    (dolist (model (schema-models schema))
      (let ((label (model-label model)))
        (when label
          (let ((field (model-field model label)))
            (cond ((null field)
                   (push (format nil "model ~a: :label refers to unknown field ~s" (model-name model) label)
                         errors))
                  ((not (member (field-type field) '(:text :slug)))
                   (push (format nil "model ~a: :label must name a text or slug field, and ~a is ~(~a~)"
                                 (model-name model) label (field-type field))
                         errors)))))))
    (nreverse errors)))

(defun check-schema (schema)
  (let ((errors (schema-errors schema)))
    (when errors
      (fail "~{~a~^; ~}" errors)))
  schema)

(defun comma-errors (where fields)
  (loop :for field :in fields
        :for comma := (find-if (lambda (option) (find #\, option)) (field-option field :options))
        :when comma
          :collect (format nil "~a: field ~s: option ~s holds a comma" where (field-name field) comma)))

(defun check-deployable (schema)
  (let ((errors (append (loop :for model :in (schema-models schema)
                              :append (comma-errors (format nil "model ~a" (model-name model)) (model-fields model)))
                        (loop :for custom :in (schema-custom-fields schema)
                              :append (comma-errors (format nil "custom field ~a" (custom-field-name custom))
                                                    (custom-field-fields custom))))))
    (when errors
      (fail "~{~a~^; ~}" errors)))
  schema)

(defun option->jvalue (key value)
  (case key
    ((:options :custom-fields) (coerce value 'vector))
    (t value)))

(defun field->jobject (field)
  (let ((obj (jobject "name" (field-name field)
                      "type" (string-downcase (symbol-name (field-type field))))))
    (let ((pairs (loop :for (k v) :on (field-options field) :by #'cddr :collect (cons k v))))
      (loop :for (k . v) :in (sort pairs #'string< :key (lambda (pair) (camel-key (car pair))))
            :do (setf (gethash (camel-key k) obj) (option->jvalue k v))))
    obj))

(defun webhook->jobject (webhook)
  (let ((obj (jobject "label" (webhook-label webhook)
                      "url" (webhook-url webhook))))
    (when (webhook-only webhook)
      (setf (gethash "only" obj) (coerce (webhook-only webhook) 'vector)))
    obj))

(defun jobject->webhook (obj)
  (unless (hash-table-p obj) (fail "each webhook must be an object"))
  (let ((label (jget obj "label")) (url (jget obj "url")))
    (make-webhook (or label url) url :only (jget obj "only"))))

(defun model->jobject (model)
  (let ((obj (jobject "name" (model-name model)
                      "kind" (string-downcase (symbol-name (model-kind model)))
                      "fields" (map 'vector #'field->jobject (model-fields model)))))
    (when (model-preview-url model) (setf (gethash "previewUrl" obj) (model-preview-url model)))
    (when (model-public-url model) (setf (gethash "publicUrl" obj) (model-public-url model)))
    (when (model-label model) (setf (gethash "label" obj) (model-label model)))
    (when (model-was model) (setf (gethash "was" obj) (model-was model)))
    obj))

(defun custom-field->jobject (custom)
  (jobject "name" (custom-field-name custom)
           "fields" (map 'vector #'field->jobject (custom-field-fields custom))))

(defun schema->jobject (schema)
  (let ((obj (jobject "koyaSchema" +schema-version+
                      "webhooks" (map 'vector #'webhook->jobject (schema-webhooks schema))
                      "models" (map 'vector #'model->jobject (schema-models schema)))))
    (when (schema-custom-fields schema)
      (setf (gethash "customFields" obj) (map 'vector #'custom-field->jobject (schema-custom-fields schema))))
    obj))

(defun jvalue->option (key value)
  (case key
    ((:options :custom-fields) (if (json-array-p value) (coerce value 'list) value))
    (t value)))

(defun find-keyword (string candidates)
  (and (stringp string)
       (find string candidates :key (lambda (k) (string-downcase (symbol-name k))) :test #'string=)))

(defparameter *option-keys*
  (remove-duplicates (append (loop :for (nil . options) :in *field-types* :append options)
                             *universal-options*)))

(defun jobject->field (obj)
  (unless (hash-table-p obj) (fail "each field must be an object"))
  (let* ((name (jget obj "name"))
         (type-string (jget obj "type"))
         (type (find-keyword type-string (mapcar #'car *field-types*)))
         (options '()))
    (unless (stringp name) (fail "field without a name"))
    (unless type (fail "field ~s has unknown type ~s" name type-string))
    (dolist (key (jkeys obj))
      (unless (member key '("name" "type") :test #'string=)
        (let ((k (find key *option-keys* :key #'camel-key :test #'string=)))
          (unless k (fail "field ~s has unknown option ~s" name key))
          (setf options (append options (list k (jvalue->option k (gethash key obj))))))))
    (apply #'make-field name type options)))

(defun jobject->custom-field (obj)
  (unless (hash-table-p obj) (fail "each custom field must be an object"))
  (let ((name (jget obj "name"))
        (fields (jget obj "fields")))
    (unless (stringp name) (fail "custom field without a name"))
    (unless (json-array-p fields) (fail "custom field ~s: fields must be an array" name))
    (make-custom-field name (map 'list #'jobject->field fields))))

(defun jobject->model (obj)
  (unless (hash-table-p obj) (fail "each model must be an object"))
  (let ((name (jget obj "name"))
        (kind (find-keyword (jget obj "kind") '(:list :object)))
        (fields (jget obj "fields")))
    (unless (stringp name) (fail "model without a name"))
    (unless kind (fail "model ~s: kind must be \"list\" or \"object\"" name))
    (unless (or (null fields) (json-array-p fields)) (fail "model ~s: fields must be an array" name))
    (make-model name kind
                (map 'list #'jobject->field (or fields #()))
                :preview-url (jget obj "previewUrl")
                :public-url (jget obj "publicUrl")
                :label (jget obj "label")
                :was (jget obj "was"))))

(defun jobject->schema (obj)
  (unless (hash-table-p obj) (fail "schema must be a JSON object"))
  (let ((version (jget obj "koyaSchema")))
    (unless (eql version +schema-version+)
      (fail "unsupported koyaSchema version ~s (expected ~a)" version +schema-version+)))
  (let ((webhooks (jget obj "webhooks"))
        (custom-fields (jget obj "customFields"))
        (models (jget obj "models")))
    (unless (or (null webhooks) (json-array-p webhooks)) (fail "webhooks must be an array"))
    (unless (or (null custom-fields) (json-array-p custom-fields)) (fail "customFields must be an array"))
    (unless (or (null models) (json-array-p models)) (fail "models must be an array"))
    (check-schema (make-schema :webhooks (coerce (or webhooks #()) 'list)
                               :custom-fields (map 'list #'jobject->custom-field (or custom-fields #()))
                               :models (map 'list #'jobject->model (or models #()))))))
