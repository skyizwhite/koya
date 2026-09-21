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
           #:field-required-p
           #:field-many-p
           #:model
           #:make-model
           #:model-name
           #:model-kind
           #:model-fields
           #:model-field
           #:model-options
           #:model-webhooks
           #:make-webhook
           #:webhook-label
           #:webhook-url
           #:webhook->jobject
           #:model-preview-url
           #:model-public-url
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
  "Space and model names: lowercase, digits and hyphens, used in URLs.
Patterns end in \\z, not $: cl-ppcre's $ also matches before a trailing newline."
  (and (stringp string) (scan "^[a-z][a-z0-9-]*\\z" string) t))

(defun field-name-p (string)
  "Field names: camelCase identifiers, used as JSON keys."
  (and (stringp string) (scan "^[a-z][a-zA-Z0-9]*\\z" string) t))

;;; ---------------------------------------------------------------------------
;;; Structures

(defstruct (field (:constructor %make-field))
  name      ; camelCase string
  type      ; keyword from *field-types*
  options)  ; plist, kebab-case keywords

(defun normalize-option (key value)
  "Options that name other things accept symbols and are stored as strings."
  (flet ((name-string (v) (if (symbolp v) (string-downcase (symbol-name v)) v)))
    (case key
      (:model (name-string value))
      (:from (if (symbolp value) (camel-key value) value))
      (:options (if (or (listp value) (json-array-p value))
                    (map 'list #'name-string value)
                    value))
      (t value))))

(defun check-option-value (field-name key value)
  "Option values come from Lisp code or from JSON sent to the server; both are
checked here so that validation never trips over a wrong type or a broken regex."
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
      (:from
       (unless (field-name-p value) (bad "a field name"))))))

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
    (%make-field :name name :type type :options options)))

(defun field-option (field key &optional default)
  (getf (field-options field) key default))

(defun field-required-p (field) (and (field-option field :required) t))
(defun field-many-p (field) (and (field-option field :many) t))

;;; ---------------------------------------------------------------------------
;;; Webhooks: plists (:label L :url U) so EQUAL compares them. Every webhook is
;;; sent every event -- publish, unpublish, delete and draft -- and the payload
;;; names the event; the receiver decides what to act on (see lib/webhook).
;;; A space's webhooks apply to every model; a model adds its own.

(defun webhook-label (webhook) (getf webhook :label))
(defun webhook-url (webhook) (getf webhook :url))

(defun make-webhook (label url)
  "A webhook: LABEL names it in plans and logs, URL receives the POST."
  (unless (and (stringp label) (plusp (length label))) (fail "webhook label must be a non-empty string, got ~s" label))
  (unless (and (stringp url) (plusp (length url))) (fail "webhook ~s: url must be a non-empty string, got ~s" label url))
  (list :label label :url url))

(defun normalize-webhook (entry)
  "ENTRY is a webhook plist from the DSL or a wire-format object."
  (cond ((and (consp entry) (keywordp (first entry)))
         (make-webhook (getf entry :label) (getf entry :url)))
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
  name      ; slug string
  kind      ; :list or :object
  fields    ; list of FIELD
  options   ; plist: :preview-url :public-url (templates with {CONTENT_ID} {DRAFT_KEY})
  webhooks) ; list of webhook plists, in addition to the space's

(defun make-model (name kind fields &key preview-url public-url webhooks)
  (let ((name (string-downcase (string name))))
    (dolist (url (list preview-url public-url))
      (unless (or (null url) (stringp url))
        (fail "model ~s: URL templates must be strings" name)))
    (unless (slug-name-p name)
      (fail "model name ~s must be lowercase letters, digits and hyphens" name))
    (unless (member kind '(:list :object))
      (fail "model ~s: kind must be :list or :object, got ~s" name kind))
    (let ((names (mapcar #'field-name fields)))
      (when (/= (length names) (length (remove-duplicates names :test #'string=)))
        (fail "model ~s has duplicate field names" name)))
    (%make-model :name name :kind kind :fields fields
                 :options (append (and preview-url (list :preview-url preview-url))
                                  (and public-url (list :public-url public-url)))
                 :webhooks (normalize-webhooks webhooks (format nil "model ~s" name)))))

(defun model-preview-url (model) (getf (model-options model) :preview-url))
(defun model-public-url (model) (getf (model-options model) :public-url))

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
    (%make-space :name name
                 :webhooks (normalize-webhooks webhooks (format nil "space ~s" name))
                 :models models)))

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
             (let* ((from (field-option field :from))
                    (source (model-field model from)))
               (cond ((null source)
                      (push (format nil "~a.~a.~a: :from refers to unknown field ~s"
                                    (space-name space) (model-name model) (field-name field) from)
                            errors))
                     ((or (eq source field) (not (member (field-type source) '(:text :textarea))))
                      (push (format nil "~a.~a.~a: :from must name a text or textarea field other than itself"
                                    (space-name space) (model-name model) (field-name field))
                            errors)))))))))
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

(defun webhook->jobject (webhook)
  (jobject "label" (webhook-label webhook)
           "url" (webhook-url webhook)))

(defun jobject->webhook (obj)
  "Any other key -- the \"events\" older schemas carried -- is ignored, so a
stored schema loads and is rewritten in the current shape on the next deploy."
  (unless (hash-table-p obj) (fail "each webhook must be an object"))
  (let ((label (jget obj "label")) (url (jget obj "url")))
    (make-webhook (or label url) url)))

(defun model->jobject (model)
  (let ((obj (jobject "name" (model-name model)
                      "kind" (string-downcase (symbol-name (model-kind model)))
                      "fields" (map 'vector #'field->jobject (model-fields model)))))
    (when (model-preview-url model) (setf (gethash "previewUrl" obj) (model-preview-url model)))
    (when (model-public-url model) (setf (gethash "publicUrl" obj) (model-public-url model)))
    (when (model-webhooks model) (setf (gethash "webhooks" obj) (map 'vector #'webhook->jobject (model-webhooks model))))
    obj))

(defun space->jobject (space)
  (jobject "name" (space-name space)
           "webhooks" (map 'vector #'webhook->jobject (space-webhooks space))
           "models" (map 'vector #'model->jobject (space-models space))))

(defun schema->jobject (schema)
  (jobject "koyaSchema" +schema-version+
           "spaces" (map 'vector #'space->jobject (schema-spaces schema))))

(defun jvalue->option (key value)
  (case key
    (:options (if (json-array-p value) (coerce value 'list) value))
    (t value)))

(defun find-keyword (string candidates)
  "The keyword in CANDIDATES whose lowercase name is STRING, or NIL. Wire input is
never interned: an unknown name stays a string."
  (and (stringp string)
       (find string candidates :key (lambda (k) (string-downcase (symbol-name k))) :test #'string=)))

(defparameter *option-keys*
  (remove-duplicates (loop :for (nil . options) :in *field-types* :append options)))

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

(defun jobject->model (obj)
  (unless (hash-table-p obj) (fail "each model must be an object"))
  (let ((name (jget obj "name"))
        (kind (find-keyword (jget obj "kind") '(:list :object)))
        (fields (jget obj "fields")))
    (unless (stringp name) (fail "model without a name"))
    (unless kind (fail "model ~s: kind must be \"list\" or \"object\"" name))
    (unless (or (null fields) (json-array-p fields)) (fail "model ~s: fields must be an array" name))
    (let ((webhooks (jget obj "webhooks")))
      (unless (or (null webhooks) (json-array-p webhooks)) (fail "model ~s: webhooks must be an array" name))
      (make-model name kind
                  (map 'list #'jobject->field (or fields #()))
                  :preview-url (jget obj "previewUrl")
                  :public-url (jget obj "publicUrl")
                  :webhooks (coerce (or webhooks #()) 'list)))))

(defun jobject->space (obj)
  (unless (hash-table-p obj) (fail "each space must be an object"))
  (let ((name (jget obj "name"))
        (webhooks (jget obj "webhooks"))
        (models (jget obj "models")))
    (unless (stringp name) (fail "space without a name"))
    (unless (or (null webhooks) (json-array-p webhooks)) (fail "space ~s: webhooks must be an array" name))
    (unless (or (null models) (json-array-p models)) (fail "space ~s: models must be an array" name))
    (make-space name
                :webhooks (coerce (or webhooks #()) 'list)
                :models (map 'list #'jobject->model (or models #())))))

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
