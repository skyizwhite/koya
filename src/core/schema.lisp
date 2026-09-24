(defpackage #:koya/core/schema
  (:use #:cl)
  (:import-from #:koya/core/case
                #:camel-key
                #:kebab-keyword)
  (:import-from #:koya/core/json
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
           #:schema->jobject
           #:jobject->schema
           #:field->jobject
           #:model->jobject
           #:jobject->model
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

;;; Options every field type accepts on top of its own. :WAS names what the field
;;; was called in the deployed schema: an instruction to the deploy, which
;;; renames and then stores the field without it.
(defparameter *universal-options* '(:was))

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
      ;; a JSON null is left alone, to fail the option's own check
      ((:from :was) (if (and value (symbolp value) (not (json-null-p value))) (camel-key value) value))
      (:options (if (or (listp value) (json-array-p value))
                    (map 'list #'name-string value)
                    value))
      (t value))))

(defun check-option-value (field-name key value)
  "Option values come from Lisp or from JSON, and are checked here so that
validation never trips over a wrong type or a broken regex."
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
       (unless (field-name-p value) (bad "a field name")))
      (:was
       (unless (field-name-p value) (bad "a field name"))
       (when (member value +system-fields+ :test #'string=)
         (fail "field ~s: :was names the system field ~s" field-name value))))))

(defun make-field (name type &rest options)
  (let ((name (if (stringp name) name (camel-key name)))
        ;; :was NIL is an option given as nothing, not a rename
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
    (when (equal (getf options :was) name)
      (fail "field ~s: :was must name the field it was renamed from, not itself" name))
    (%make-field :name name :type type :options options)))

(defun field-option (field key &optional default)
  (getf (field-options field) key default))

(defun field-was (field)
  "The name FIELD had in the deployed schema, or NIL."
  (field-option field :was))

(defun forget-rename (options)
  "OPTIONS without :WAS: a rename takes no part in comparing shapes, and is not
stored."
  (loop :for (key value) :on options :by #'cddr
        :unless (eq key :was) :append (list key value)))

(defun field-forget-rename (field)
  "FIELD as the server stores it: without its :WAS."
  (if (field-was field)
      (%make-field :name (field-name field) :type (field-type field)
                   :options (forget-rename (field-options field)))
      field))

(defun field-required-p (field) (and (field-option field :required) t))
(defun field-many-p (field) (and (field-option field :many) t))

;;; ---------------------------------------------------------------------------
;;; Webhooks: plists (:label L :url U :only (M...)), so EQUAL compares them. They
;;; belong to the space and fire for every model unless :ONLY narrows them; every
;;; one is sent every event (see features/webhooks/notify).

(defun webhook-label (webhook) (getf webhook :label))
(defun webhook-url (webhook) (getf webhook :url))
(defun webhook-only (webhook)
  "The model names this webhook is narrowed to, or NIL for every model."
  (getf webhook :only))

(defun webhook-covers-p (webhook model-name)
  "True when WEBHOOK fires for the model named MODEL-NAME."
  (let ((only (webhook-only webhook)))
    (or (null only) (and (member model-name only :test #'string=) t))))

(defun normalize-only (label only)
  "ONLY is a model name or a list of them, from the DSL (symbols allowed) or the
wire. Returns a list of strings, or NIL for every model."
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

(defun make-webhook (label url &key only)
  "A webhook: LABEL names it in plans and logs, URL receives the POST. ONLY is a
model name, or a list of them, to narrow it to; without it the webhook fires for
every model of the space."
  (unless (and (stringp label) (plusp (length label))) (fail "webhook label must be a non-empty string, got ~s" label))
  (unless (and (stringp url) (plusp (length url))) (fail "webhook ~s: url must be a non-empty string, got ~s" label url))
  (let ((only (normalize-only label only)))
    (append (list :label label :url url) (and only (list :only only)))))

(defun normalize-webhook (entry)
  "ENTRY is a webhook plist from the DSL or a wire-format object."
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
  name     ; slug string
  kind     ; :list or :object
  fields   ; list of FIELD
  options) ; plist: :preview-url :public-url (templates with {CONTENT_ID} {DRAFT_KEY}),
           ; :label (the field naming a content), :was

(defun check-field-renames (model-name fields)
  "A field's :WAS must name one field, once, and one this model no longer declares."
  (let ((names (mapcar #'field-name fields))
        (renames (remove nil (mapcar #'field-was fields))))
    (when (/= (length renames) (length (remove-duplicates renames :test #'string=)))
      (fail "model ~s: two fields are renamed from the same field" model-name))
    (dolist (was renames)
      (when (member was names :test #'string=)
        (fail "model ~s: a field is renamed from ~s, which the model still declares" model-name was)))))

(defun name-designator (value)
  "VALUE as a lowercase name, or VALUE itself when it is not one -- a number, or a
JSON null -- which then fails the check that reads it rather than passing as a
thing called \"null\"."
  (cond ((json-null-p value) value)
        ((stringp value) (string-downcase value))
        ((and value (symbolp value)) (string-downcase (symbol-name value)))
        (t value)))

(defun make-model (name kind fields &key preview-url public-url label was)
  (let ((name (string-downcase (string name)))
        (was (name-designator was))
        ;; a field name, as :from on a slug takes it
        (label (if (and label (symbolp label) (not (json-null-p label))) (camel-key label) label)))
    (dolist (url (list preview-url public-url))
      (unless (or (null url) (stringp url))
        (fail "model ~s: URL templates must be strings" name)))
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
  "The name of the field whose value names a content of MODEL, or NIL: which
field that is only the schema can say."
  (getf (model-options model) :label))

(defun model-was (model)
  "The name MODEL had in the deployed schema, or NIL."
  (getf (model-options model) :was))

(defun model-forget-renames (model)
  "MODEL as the server stores it: no :WAS, on it or on its fields."
  (%make-model :name (model-name model) :kind (model-kind model)
               :fields (mapcar #'field-forget-rename (model-fields model))
               :options (forget-rename (model-options model))))

(defun model-field (model name)
  (find (if (stringp name) name (camel-key name)) (model-fields model)
        :key #'field-name :test #'string=))

;;; A schema is one space's models and webhooks. The space itself is made in the
;;; admin UI and is not part of the document; its name travels in the deploy URL.

(defstruct (schema (:constructor %make-schema))
  webhooks  ; list of webhook plists, fired by every model
  models)   ; list of MODEL

(defun make-schema (&key webhooks models)
  (let ((names (mapcar #'model-name models)))
    (when (/= (length names) (length (remove-duplicates names :test #'string=)))
      (fail "duplicate model names")))
  (%make-schema :webhooks (normalize-webhooks webhooks "schema") :models models))

(defun schema-model (schema name)
  (find (string-downcase (string name)) (schema-models schema) :key #'model-name :test #'string=))

;;; ---------------------------------------------------------------------------
;;; Semantic checks that need the whole schema (cross references).

(defun schema-errors (schema)
  "Return a list of human readable problems, empty when the schema is consistent."
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
  (let ((obj (jobject "label" (webhook-label webhook)
                      "url" (webhook-url webhook))))
    (when (webhook-only webhook)
      (setf (gethash "only" obj) (coerce (webhook-only webhook) 'vector)))
    obj))

(defun jobject->webhook (obj)
  "Any other key -- the \"events\" older schemas carried -- is ignored, so a
stored schema loads and is rewritten in the current shape on the next deploy."
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

(defun schema->jobject (schema)
  (jobject "koyaSchema" +schema-version+
           "webhooks" (map 'vector #'webhook->jobject (schema-webhooks schema))
           "models" (map 'vector #'model->jobject (schema-models schema))))

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

(defun jobject->model (obj)
  (unless (hash-table-p obj) (fail "each model must be an object"))
  (let ((name (jget obj "name"))
        (kind (find-keyword (jget obj "kind") '(:list :object)))
        (fields (jget obj "fields")))
    (unless (stringp name) (fail "model without a name"))
    (unless kind (fail "model ~s: kind must be \"list\" or \"object\"" name))
    (unless (or (null fields) (json-array-p fields)) (fail "model ~s: fields must be an array" name))
    ;; a "webhooks" key from a schema stored before they all moved to the space is
    ;; ignored, like the "events" of an older webhook
    (make-model name kind
                (map 'list #'jobject->field (or fields #()))
                :preview-url (jget obj "previewUrl")
                :public-url (jget obj "publicUrl")
                :label (jget obj "label")
                :was (jget obj "was"))))

(defun jobject->schema (obj)
  "Parse a wire-format schema object. Signals SCHEMA-ERROR on malformed input."
  (unless (hash-table-p obj) (fail "schema must be a JSON object"))
  (let ((version (jget obj "koyaSchema")))
    (unless (eql version +schema-version+)
      (fail "unsupported koyaSchema version ~s (expected ~a)" version +schema-version+)))
  (let ((webhooks (jget obj "webhooks"))
        (models (jget obj "models")))
    (unless (or (null webhooks) (json-array-p webhooks)) (fail "webhooks must be an array"))
    (unless (or (null models) (json-array-p models)) (fail "models must be an array"))
    (check-schema (make-schema :webhooks (coerce (or webhooks #()) 'list)
                               :models (map 'list #'jobject->model (or models #()))))))
