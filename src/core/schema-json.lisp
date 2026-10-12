(defpackage #:koya-core/schema-json
  (:use #:cl)
  (:import-from #:koya-core/case
                #:camel-key)
  (:import-from #:koya-core/json
                #:jobject
                #:jget
                #:jkeys
                #:json-null-p)
  (:import-from #:koya-core/data #:array-p)
  (:import-from #:koya-core/schema
                #:+schema-version+ #:*field-types* #:+option-keys+ #:schema-error
                #:field-name #:field-type #:field-options #:make-field
                #:custom-field-name #:custom-field-fields #:make-custom-field
                #:webhook-label #:webhook-url #:webhook-only #:make-webhook
                #:model-name #:model-kind #:model-fields #:model-preview-url #:model-public-url
                #:model-label #:model-was #:make-model
                #:schema-webhooks #:schema-custom-fields #:schema-models #:make-schema #:check-schema)
  (:import-from #:koya-core/diff
                #:change-path #:destructive-change-p #:format-change)
  (:export #:schema->jobject
           #:jobject->schema
           #:field->jobject
           #:model->jobject
           #:jobject->model
           #:custom-field->jobject
           #:jobject->custom-field
           #:webhook->jobject
           #:jobject->webhook
           #:forget-slug-options
           #:change->jobject))
(in-package #:koya-core/schema-json)

(defun fail (fmt &rest args)
  (error 'schema-error :message (apply #'format nil fmt args)))

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
  (let ((label (jget obj "label")) (url (jget obj "url")) (only (jget obj "only")))
    (when (json-null-p only) (fail "webhook ~s: only is null" (or label url)))
    (make-webhook (or label url) url :only (if (array-p only) (coerce only 'list) only))))

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
    ((:options :custom-fields) (if (array-p value) (coerce value 'list) value))
    (t value)))

(defun find-keyword (string candidates)
  (and (stringp string)
       (find string candidates :key (lambda (k) (string-downcase (symbol-name k))) :test #'string=)))

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
        (let ((k (find key +option-keys+ :key #'camel-key :test #'string=))
              (value (gethash key obj)))
          (unless k (fail "field ~s has unknown option ~s" name key))
          (when (json-null-p value) (fail "field ~s: option ~s is null" name key))
          (setf options (append options (list k (jvalue->option k value)))))))
    (apply #'make-field name type options)))

(defun jobject->custom-field (obj)
  (unless (hash-table-p obj) (fail "each custom field must be an object"))
  (let ((name (jget obj "name"))
        (fields (jget obj "fields")))
    (unless (stringp name) (fail "custom field without a name"))
    (unless (array-p fields) (fail "custom field ~s: fields must be an array" name))
    (make-custom-field name (map 'list #'jobject->field fields))))

(defun forget-slug-options (obj)
  (let ((fields (and (hash-table-p obj) (jget obj "fields")))
        (forgot nil))
    (when (array-p fields)
      (loop :for field :across fields
            :when (and (hash-table-p field) (equal (jget field "type") "slug"))
              :do (let ((from (remhash "from" field))
                        (unique (remhash "unique" field)))
                    (when (or from unique) (setf forgot t)))))
    forgot))

(defun model-value (obj name key)
  (let ((value (jget obj key)))
    (when (json-null-p value) (fail "model ~s: ~a is null" name key))
    value))

(defun jobject->model (obj)
  (unless (hash-table-p obj) (fail "each model must be an object"))
  (let ((name (jget obj "name"))
        (kind (find-keyword (jget obj "kind") '(:list :object)))
        (fields (jget obj "fields")))
    (unless (stringp name) (fail "model without a name"))
    (unless kind (fail "model ~s: kind must be \"list\" or \"object\"" name))
    (unless (or (null fields) (array-p fields)) (fail "model ~s: fields must be an array" name))
    (make-model name kind
                (map 'list #'jobject->field (or fields #()))
                :preview-url (model-value obj name "previewUrl")
                :public-url (model-value obj name "publicUrl")
                :label (model-value obj name "label")
                :was (model-value obj name "was"))))

(defun jobject->schema (obj)
  (unless (hash-table-p obj) (fail "schema must be a JSON object"))
  (let ((version (jget obj "koyaSchema")))
    (unless (eql version +schema-version+)
      (fail "unsupported koyaSchema version ~s (expected ~a)" version +schema-version+)))
  (let ((webhooks (jget obj "webhooks"))
        (custom-fields (jget obj "customFields"))
        (models (jget obj "models")))
    (unless (or (null webhooks) (array-p webhooks)) (fail "webhooks must be an array"))
    (unless (or (null custom-fields) (array-p custom-fields)) (fail "customFields must be an array"))
    (unless (or (null models) (array-p models)) (fail "models must be an array"))
    (check-schema (make-schema :webhooks (map 'list #'jobject->webhook (or webhooks #()))
                               :custom-fields (map 'list #'jobject->custom-field (or custom-fields #()))
                               :models (map 'list #'jobject->model (or models #()))))))

(defun misfit->jobject (misfit)
  (jobject "id" (getf misfit :id)
           "field" (getf misfit :field)
           "version" (getf misfit :version)
           "message" (getf misfit :message)))

(defun change->jobject (change)
  (let ((object (jobject "op" (string-downcase (substitute #\_ #\- (symbol-name (getf change :op))))
                         "path" (change-path change)
                         "destructive" (destructive-change-p change)
                         "description" (string-trim " " (format-change change)))))
    (when (getf change :misfits)
      (setf (gethash "misfits" object) (map 'vector #'misfit->jobject (getf change :misfits))))
    object))
