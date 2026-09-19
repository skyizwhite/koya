(defpackage #:koya/core/schema
  (:use #:cl)
  (:import-from #:koya/core/case
                #:camel-key
                #:kebab-keyword)
  (:import-from #:koya/core/json
                #:jobject
                #:jget
                #:jkeys
                #:json-array-p)
  (:import-from #:cl-ppcre
                #:scan)
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
           #:field-required-p
           #:field-many-p
           #:model
           #:make-model
           #:model-name
           #:model-kind
           #:model-fields
           #:model-field
           #:space-def
           #:make-space
           #:space-name
           #:space-webhooks
           #:space-models
           #:space-model
           #:schema
           #:make-schema
           #:schema-spaces
           #:schema-space
           #:schema-error
           #:schema-error-message
           #:schema-errors
           #:check-schema
           #:schema->jobject
           #:jobject->schema
           #:field->jobject
           #:model->jobject
           #:jobject->model
           #:space->jobject
           #:jobject->space
           #:slug-name-p
           #:field-name-p))
(in-package #:koya/core/schema)

(defparameter +schema-version+ 1)

;;; Fields every content has; they are managed by the server and cannot be
;;; declared in a model.
(defparameter +system-fields+ '("id" "createdAt" "updatedAt" "publishedAt" "revisedAt"))

;;; Field types and the options each accepts. Option names are kebab-case
;;; keywords in Lisp and camelCase strings on the wire.
(defparameter *field-types*
  '((:text      :required :max-length :pattern :unique)
    (:textarea  :required :max-length)
    (:richtext  :required)
    (:number    :required :min :max :integer)
    (:boolean   :required :default)
    (:date      :required)
    (:datetime  :required)
    (:select    :required :options :many)
    (:media     :required)
    (:reference :required :model :many)
    (:slug      :required :from :unique :pattern)))

(defun field-type-p (type)
  (and (assoc type *field-types*) t))

(defun field-type-options (type)
  (rest (assoc type *field-types*)))

(define-condition schema-error (error)
  ((message :initarg :message :reader schema-error-message))
  (:report (lambda (c s) (format s "Invalid schema: ~a" (schema-error-message c)))))

(defun fail (fmt &rest args)
  (error 'schema-error :message (apply #'format nil fmt args)))

(defun slug-name-p (string)
  "Space and model names: lowercase, digits and hyphens, used in URLs."
  (and (stringp string) (scan "^[a-z][a-z0-9-]*$" string) t))

(defun field-name-p (string)
  "Field names: camelCase identifiers, used as JSON keys."
  (and (stringp string) (scan "^[a-z][a-zA-Z0-9]*$" string) t))

;;; ---------------------------------------------------------------------------
;;; Structures

(defstruct (field (:constructor %make-field))
  name      ; camelCase string
  type      ; keyword from *field-types*
  options)  ; plist, kebab-case keywords

(defun normalize-option (key value)
  "Options that name other things accept symbols and are stored as strings."
  (case key
    (:model (string-downcase (string value)))
    (:from (camel-key value))
    (:options (mapcar #'string (coerce value 'list)))
    (t value)))

(defun make-field (name type &rest options)
  (let ((name (if (stringp name) name (camel-key name)))
        (options (loop :for (k v) :on options :by #'cddr
                       :append (list k (normalize-option k v)))))
    (unless (field-name-p name)
      (fail "field name ~s must be a camelCase identifier" name))
    (when (member name +system-fields+ :test #'string=)
      (fail "field name ~s is reserved for a system field" name))
    (unless (field-type-p type)
      (fail "unknown field type ~s for field ~s" type name))
    (loop :for (k nil) :on options :by #'cddr
          :unless (member k (field-type-options type))
            :do (fail "option ~s is not allowed on ~a field ~s" k type name))
    (when (and (eq type :select) (null (getf options :options)))
      (fail "select field ~s needs :options" name))
    (when (and (eq type :reference) (null (getf options :model)))
      (fail "reference field ~s needs :model" name))
    (when (and (eq type :slug) (null (getf options :from)))
      (fail "slug field ~s needs :from" name))
    (%make-field :name name :type type :options options)))

(defun field-option (field key &optional default)
  (getf (field-options field) key default))

(defun field-required-p (field) (and (field-option field :required) t))
(defun field-many-p (field) (and (field-option field :many) t))

(defstruct (model (:constructor %make-model))
  name    ; slug string
  kind    ; :list or :object
  fields) ; list of FIELD

(defun make-model (name kind fields)
  (let ((name (string-downcase (string name))))
    (unless (slug-name-p name)
      (fail "model name ~s must be lowercase letters, digits and hyphens" name))
    (unless (member kind '(:list :object))
      (fail "model ~s: kind must be :list or :object, got ~s" name kind))
    (let ((names (mapcar #'field-name fields)))
      (when (/= (length names) (length (remove-duplicates names :test #'string=)))
        (fail "model ~s has duplicate field names" name)))
    (%make-model :name name :kind kind :fields fields)))

(defun model-field (model name)
  (find (if (stringp name) name (camel-key name)) (model-fields model)
        :key #'field-name :test #'string=))

(defstruct (space-def (:conc-name space-) (:constructor %make-space))
  name      ; slug string
  webhooks  ; list of URL strings
  models)   ; list of MODEL

(defun make-space (name &key webhooks models)
  (let ((name (string-downcase (string name))))
    (unless (slug-name-p name)
      (fail "space name ~s must be lowercase letters, digits and hyphens" name))
    (let ((names (mapcar #'model-name models)))
      (when (/= (length names) (length (remove-duplicates names :test #'string=)))
        (fail "space ~s has duplicate model names" name)))
    (%make-space :name name :webhooks webhooks :models models)))

(defun space-model (space name)
  (find (string-downcase (string name)) (space-models space) :key #'model-name :test #'string=))

(defstruct (schema (:constructor %make-schema))
  spaces)

(defun make-schema (&optional spaces)
  (let ((names (mapcar #'space-name spaces)))
    (when (/= (length names) (length (remove-duplicates names :test #'string=)))
      (fail "duplicate space names")))
  (%make-schema :spaces spaces))

(defun schema-space (schema name)
  (find (string-downcase (string name)) (schema-spaces schema) :key #'space-name :test #'string=))

;;; ---------------------------------------------------------------------------
;;; Semantic checks that need the whole schema (cross references).

(defun schema-errors (schema)
  "Return a list of human readable problems, empty when the schema is consistent."
  (let ((errors '()))
    (dolist (space (schema-spaces schema))
      (dolist (model (space-models space))
        (dolist (field (model-fields model))
          (case (field-type field)
            (:reference
             (let ((target (field-option field :model)))
               (unless (space-model space target)
                 (push (format nil "~a.~a.~a references unknown model ~s"
                               (space-name space) (model-name model) (field-name field) target)
                       errors))))
            (:slug
             (let ((from (field-option field :from)))
               (unless (model-field model from)
                 (push (format nil "~a.~a.~a: :from refers to unknown field ~s"
                               (space-name space) (model-name model) (field-name field) from)
                       errors))))))))
    (nreverse errors)))

(defun check-schema (schema)
  "Signal SCHEMA-ERROR when SCHEMA is inconsistent, otherwise return it."
  (let ((errors (schema-errors schema)))
    (when errors
      (fail "~{~a~^; ~}" errors)))
  schema)

;;; ---------------------------------------------------------------------------
;;; Wire format (JSON objects as EQUAL hash tables).

(defun option->jvalue (key value)
  (case key
    (:options (coerce value 'vector))
    (t value)))

(defun field->jobject (field)
  (let ((obj (jobject "name" (field-name field)
                      "type" (string-downcase (symbol-name (field-type field))))))
    ;; Options are emitted in sorted key order so that serialization is stable
    ;; regardless of how the field was constructed.
    (let ((pairs (loop :for (k v) :on (field-options field) :by #'cddr :collect (cons k v))))
      (loop :for (k . v) :in (sort pairs #'string< :key (lambda (pair) (camel-key (car pair))))
            :do (setf (gethash (camel-key k) obj) (option->jvalue k v))))
    obj))

(defun model->jobject (model)
  (jobject "name" (model-name model)
           "kind" (string-downcase (symbol-name (model-kind model)))
           "fields" (map 'vector #'field->jobject (model-fields model))))

(defun space->jobject (space)
  (jobject "name" (space-name space)
           "webhooks" (coerce (space-webhooks space) 'vector)
           "models" (map 'vector #'model->jobject (space-models space))))

(defun schema->jobject (schema)
  (jobject "koyaSchema" +schema-version+
           "spaces" (map 'vector #'space->jobject (schema-spaces schema))))

(defun jvalue->option (key value)
  (case key
    (:options (coerce value 'list))
    (t value)))

(defun jobject->field (obj)
  (let* ((name (jget obj "name"))
         (type-string (jget obj "type"))
         (type (and (stringp type-string) (intern (string-upcase type-string) :keyword)))
         (options '()))
    (unless (stringp name) (fail "field without a name"))
    (unless (and type (field-type-p type)) (fail "field ~s has unknown type ~s" name type-string))
    (dolist (key (jkeys obj))
      (unless (member key '("name" "type") :test #'string=)
        (let ((k (kebab-keyword key)))
          (setf options (append options (list k (jvalue->option k (gethash key obj))))))))
    (apply #'make-field name type options)))

(defun jobject->model (obj)
  (let ((kind (jget obj "kind"))
        (fields (jget obj "fields")))
    (unless (stringp kind) (fail "model ~s without kind" (jget obj "name")))
    (make-model (or (jget obj "name") (fail "model without a name"))
                (intern (string-upcase kind) :keyword)
                (map 'list #'jobject->field (or fields #())))))

(defun jobject->space (obj)
  (make-space (or (jget obj "name") (fail "space without a name"))
              :webhooks (coerce (or (jget obj "webhooks") #()) 'list)
              :models (map 'list #'jobject->model (or (jget obj "models") #()))))

(defun jobject->schema (obj)
  "Parse a wire-format schema object. Signals SCHEMA-ERROR on malformed input."
  (unless (hash-table-p obj) (fail "schema must be a JSON object"))
  (let ((version (jget obj "koyaSchema")))
    (unless (eql version +schema-version+)
      (fail "unsupported koyaSchema version ~s (expected ~a)" version +schema-version+)))
  (let ((spaces (jget obj "spaces")))
    (unless (or (null spaces) (json-array-p spaces))
      (fail "spaces must be an array"))
    (check-schema (make-schema (map 'list #'jobject->space (or spaces #()))))))
