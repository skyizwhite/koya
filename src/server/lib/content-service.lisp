(defpackage #:koya-server/lib/content-service
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-kind #:model-fields #:field-name #:field-option #:space-model #:space-name)
  (:import-from #:koya/core/validate
                #:validate-content #:validation-error #:blank-value-p)
  (:import-from #:koya/core/json
                #:json-null)
  (:import-from #:koya-server/db/schema-store
                #:find-space)
  (:import-from #:koya-server/db/contents
                #:create-content #:save-draft #:publish-content #:unpublish-content #:delete-content
                #:find-content #:find-object-content #:unique-value-taken-p
                #:content-id #:content-published #:content-draft #:content-published-at #:content-data)
  (:import-from #:koya-server/lib/presenter
                #:content->jobject)
  (:import-from #:koya-server/lib/webhook
                #:notify-webhooks)
  (:import-from #:koya-server/lib/http
                #:fail-api)
  (:import-from #:koya-server/lib/forms
                #:slugify)
  (:export #:resolve-model
           #:resolve-content
           #:check-content
           #:merge-data
           #:create
           #:update-draft
           #:publish
           #:unpublish
           #:destroy))
(in-package #:koya-server/lib/content-service)

;;; Content operations shared by the admin API and the admin UI: model lookup,
;;; validation (including uniqueness), persistence and webhook notification.

(defun resolve-model (space-name model-name)
  "Return (values space model) or signal 404."
  (let* ((space (or (find-space space-name) (fail-api 404 "not_found" (format nil "Space ~a does not exist" space-name))))
         (model (or (space-model space model-name) (fail-api 404 "not_found" (format nil "Model ~a does not exist" model-name)))))
    (values space model)))

(defun resolve-content (space-name model-name id)
  (or (find-content space-name model-name id)
      (fail-api 404 "not_found" (format nil "Content ~a does not exist" id))))

(defun fill-slugs (model data)
  "Generate blank :slug fields from their :from source field (destructively)."
  (dolist (field (model-fields model))
    (when (eq (koya/core/schema:field-type field) :slug)
      (let ((current (gethash (field-name field) data))
            (source (gethash (field-option field :from) data)))
        (when (and (blank-value-p current) (stringp source) (not (blank-value-p source)))
          (let ((slug (slugify source)))
            (when (plusp (length slug))
              (setf (gethash (field-name field) data) slug)))))))
  data)

(defun check-content (space-name model data &key partial exclude-id)
  "Validate DATA against MODEL, including :unique fields. Signals VALIDATION-ERROR."
  (fill-slugs model data)
  (let ((errors (validate-content model data :partial partial)))
    (dolist (field (model-fields model))
      (when (field-option field :unique)
        (multiple-value-bind (value found) (gethash (field-name field) data)
          (when (and found (not (blank-value-p value))
                     (unique-value-taken-p space-name (koya/core/schema:model-name model) (field-name field) value
                                           :exclude-id exclude-id))
            (setf errors (append errors (list (list :field (field-name field) :code "unique"
                                                    :message "must be unique"))))))))
    (when errors
      (error 'validation-error :errors errors))
    data))

(defun merge-data (base patch)
  "A new object with PATCH's keys applied on top of BASE. JSON null removes a key."
  (let ((out (make-hash-table :test 'equal)))
    (when base (maphash (lambda (k v) (setf (gethash k out) v)) base))
    (maphash (lambda (k v) (if (eq v json-null) (remhash k out) (setf (gethash k out) v))) patch)
    out))

(defun notify (space model-name content type &key old)
  (notify-webhooks space model-name (content-id content) type
                   :old old
                   :new (and (content-published content)
                             (content->jobject content (space-model space model-name) space :depth 0))))

(defun create (space model data &key publish)
  "Create a content. For object-kind models the single existing content is updated instead."
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model)))
    (check-content space-name model data)
    (if (eq (model-kind model) :object)
        (let ((existing (find-object-content space-name model-name)))
          (if existing
              (if publish (publish space model (content-id existing) data) (update-draft space model (content-id existing) data :replace t))
              (let ((content (create-content space-name model-name data :publish publish)))
                (when publish (notify space model-name content "new"))
                content)))
        (let ((content (create-content space-name model-name data :publish publish)))
          (when publish (notify space model-name content "new"))
          content))))

(defun update-draft (space model id patch &key replace)
  "Save a draft: PATCH is merged onto the current draft (or published data) unless REPLACE."
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (data (if replace patch (merge-data (content-data content :draft t) patch))))
    (check-content space-name model data :exclude-id id)
    (save-draft id data)))

(defun publish (space model id &optional data)
  "Publish DATA, or the current draft. Fires webhooks."
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (data (or data (content-data content :draft t)))
         (old (and (content-published content) (content->jobject content model space :depth 0)))
         (type (if (content-published-at content) "edit" "new")))
    (check-content space-name model data :exclude-id id)
    (let ((published (publish-content id data)))
      (notify space model-name published type :old old)
      published)))

(defun unpublish (space model id)
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (old (and (content-published content) (content->jobject content model space :depth 0))))
    (let ((result (unpublish-content id)))
      (when old (notify space model-name result "edit" :old old))
      result)))

(defun destroy (space model id)
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (old (and (content-published content) (content->jobject content model space :depth 0))))
    (delete-content id)
    (when old
      (notify-webhooks space model-name id "delete" :old old))
    t))
