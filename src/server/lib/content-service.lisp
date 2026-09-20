(defpackage #:koya-server/lib/content-service
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:model-kind #:model-fields #:field-name #:field-option #:space-model #:space-name)
  (:import-from #:koya/core/validate
                #:validate-content #:validation-error #:blank-value-p #:content-id-p)
  (:import-from #:koya/core/time
                #:parse-iso)
  (:import-from #:koya/core/json
                #:json-null)
  (:import-from #:koya-server/db/schema-store
                #:find-space #:space-webhook-secret)
  (:import-from #:koya-server/db/contents
                #:create-content #:save-draft #:publish-content #:unpublish-content #:delete-content
                #:find-content #:find-object-content #:unique-value-taken-p #:get-content
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

(defun check-timestamp (name value)
  "VALUE is an ISO 8601 string or NIL. Signals 400 naming the wire field NAME otherwise."
  (cond ((null value) nil)
        ((parse-iso value) value)
        (t (fail-api 400 "bad_request" (format nil "\"~a\" must be an ISO 8601 datetime" name)))))

(defun check-published-at (value)
  (check-timestamp "publishedAt" value))

(defun check-new-id (id)
  (cond ((null id) nil)
        ((not (content-id-p id)) (fail-api 400 "bad_request" "\"id\" must be 1-64 letters, digits, '-' or '_'"))
        ((get-content id) (fail-api 409 "conflict" (format nil "Content ~a already exists" id)))
        (t id)))

(defun published-view (space model content)
  (and (content-published content)
       (content->jobject content model space :depth 0)))

(defun notify (space model-name id type &key old new)
  (notify-webhooks space model-name id type
                   :secret (space-webhook-secret (space-name space))
                   :old old
                   :new new))

(defun create (space model data &key publish id created-at updated-at published-at revised-at)
  "Create a content. ID and the system timestamps CREATED-AT, UPDATED-AT,
PUBLISHED-AT and REVISED-AT (ISO 8601) may be given explicitly, e.g. when
importing. For object-kind models the single existing content is updated instead,
and only PUBLISHED-AT applies."
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (created-at (check-timestamp "createdAt" created-at))
         (updated-at (check-timestamp "updatedAt" updated-at))
         (published-at (check-published-at published-at))
         (revised-at (check-timestamp "revisedAt" revised-at)))
    (check-content space-name model data)
    (flet ((insert ()
             (let ((content (apply #'create-content space-name model-name data
                                   :publish publish
                                   :created-at created-at :updated-at updated-at
                                   :published-at published-at :revised-at revised-at
                                   (and (check-new-id id) (list :id id)))))
               (when publish
                 (notify space model-name (content-id content) "new" :new (published-view space model content)))
               content)))
      (if (eq (model-kind model) :object)
          (let ((existing (find-object-content space-name model-name)))
            (cond ((null existing) (insert))
                  (publish (publish space model (content-id existing) data :published-at published-at))
                  (t (update-draft space model (content-id existing) data :replace t))))
          (insert)))))

(defun update-draft (space model id patch &key replace)
  "Save a draft: PATCH is merged onto the current draft (or published data) unless REPLACE."
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (data (if replace patch (merge-data (content-data content :draft t) patch))))
    (check-content space-name model data :exclude-id id)
    (save-draft id data)))

(defun publish (space model id &optional data &key published-at)
  "Publish DATA, or the current draft. PUBLISHED-AT (ISO 8601) overrides the publish date. Fires webhooks."
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (data (or data (content-data content :draft t)))
         (published-at (check-published-at published-at))
         (old (published-view space model content))
         (type (if (content-published-at content) "edit" "new")))
    (check-content space-name model data :exclude-id id)
    (let ((published (publish-content id data :published-at published-at)))
      (notify space model-name id type :old old :new (published-view space model published))
      published)))

(defun unpublish (space model id)
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (old (published-view space model content)))
    (let ((result (unpublish-content id)))
      (when old (notify space model-name id "edit" :old old))
      result)))

(defun destroy (space model id)
  (let* ((space-name (space-name space))
         (model-name (koya/core/schema:model-name model))
         (content (resolve-content space-name model-name id))
         (old (published-view space model content)))
    (delete-content id)
    (when old (notify space model-name id "delete" :old old))
    t))
