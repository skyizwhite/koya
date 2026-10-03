(defpackage #:koya-server/usecases/contents
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:model-kind #:model-fields #:field-name #:field-option #:model-name)
  (:import-from #:koya-core/validate
                #:validate-content #:validation-error #:blank-value-p #:content-id-p #:datetime-string-p
                #:validation-error-errors)
  (:import-from #:koya-core/time #:parse-iso #:format-iso)
  (:import-from #:koya-core/json #:json-null)
  (:import-from #:koya-core/ulid #:make-ulid)
  (:import-from #:koya-server/domain/errors
                #:fail #:conflict #:invalid-input #:not-found #:koya-error #:koya-error-message)
  (:import-from #:koya-server/usecases/ports/store #:with-transaction)
  (:import-from #:koya-server/usecases/ports/spaces
                #:space-webhook-secret #:load-schema)
  (:import-from #:koya-server/usecases/ports/contents
                #:insert-content #:update-content #:delete-content #:record-revision
                #:find-object-content #:unique-value-taken-p #:get-content #:find-content
                #:contents-mentioning)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-space #:content-published #:content-draft #:content-draft-key #:content-data
                #:merge-data #:same-data-p #:fill-defaults #:fill-slugs #:to-the-minute #:new-content #:drafted #:published
                #:unpublished #:discarded #:keyed #:content-status #:next-status #:check-transition)
  (:import-from #:koya-server/usecases/delivery #:deliver)
  (:import-from #:koya-server/usecases/webhooks #:notify-webhooks)
  (:import-from #:koya-server/usecases/actor #:*actor*)
  (:import-from #:koya-server/usecases/schema #:resolve-model)
  (:import-from #:koya-server/domain/references #:reference-fields #:refers-p)
  (:export #:check-content
           #:create
           #:update-draft
           #:publish
           #:unpublish
           #:discard
           #:destroy
           #:draft-key
           #:resolve-content
           #:find-content
           #:bulk-action-p
           #:apply-to-each
           #:content-references))
(in-package #:koya-server/usecases/contents)

(defun check-content (space-name model data &key partial exclude-id)
  (fill-slugs model data)
  (let ((errors (validate-content model data :partial partial)))
    (dolist (field (model-fields model))
      (when (field-option field :unique)
        (multiple-value-bind (value found) (gethash (field-name field) data)
          (when (and found (not (blank-value-p value))
                     (unique-value-taken-p space-name (model-name model) (field-name field) value
                                           :exclude-id exclude-id))
            (setf errors (append errors (list (list :field (field-name field) :code "unique"
                                                    :message "must be unique"))))))))
    (when errors
      (error 'validation-error :errors errors))
    data))

(defun check-timestamp (name value)
  (cond ((null value) nil)
        ((datetime-string-p value) (format-iso (parse-iso value)))
        (t (fail 'invalid-input (format nil "\"~a\" must be an ISO 8601 datetime" name)))))

(defun check-published-at (value)
  (check-timestamp "publishedAt" value))

(defun check-new-id (space id)
  (cond ((null id) nil)
        ((not (content-id-p id)) (fail 'invalid-input "\"id\" must be 1-64 letters, digits, '-' or '_'"))
        ((string= id "new") (fail 'invalid-input "\"id\" cannot be \"new\""))
        ((get-content space id) (fail 'conflict (format nil "Content ~a already exists" id)))
        (t id)))

(defun published-view (space model content)
  (and (content-published content)
       (deliver content model space)))

(defun draft-view (space model content)
  (deliver content model space :draft t))

(defun notify (space model id event &key old new)
  (notify-webhooks space model id event
                   :secret (space-webhook-secret space)
                   :old old
                   :new new))

(defun store (content event data)
  (update-content content)
  (record-revision (content-space content) (content-id content) event data :by *actor*)
  content)

(defun create (space model data &key publish id created-at updated-at published-at revised-at)
  (let* ((space-name space)
         (model-name (model-name model))
         (created-at (check-timestamp "createdAt" created-at))
         (updated-at (check-timestamp "updatedAt" updated-at))
         (published-at (check-published-at published-at))
         (revised-at (check-timestamp "revisedAt" revised-at)))
    (fill-defaults model data)
    (to-the-minute model data)
    (let ((content
            (with-transaction
              (when (and (eq (model-kind model) :object) (find-object-content space-name model-name))
                (fail 'conflict (format nil "~a already has its content; change that one instead" model-name)
                      :code "object_exists"))
              (check-content space-name model data)
              (let ((content (new-content (or (check-new-id space-name id) (make-ulid)) space-name model-name data
                                          :publish publish
                                          :created-at created-at :updated-at updated-at
                                          :published-at published-at :revised-at revised-at)))
                (insert-content content)
                (record-revision space-name (content-id content) (if publish "publish" "draft") data :by *actor*)
                content))))
      (if publish
          (notify space model (content-id content) :publish :new (published-view space model content))
          (notify space model (content-id content) :draft :new (draft-view space model content)))
      content)))

(defun update-draft (space model id patch &key replace)
  (multiple-value-bind (saved outcome old)
      (with-transaction (update-draft-now space model id patch replace))
    (case outcome
      (:saved (notify space model id :draft :old (published-view space model saved) :new (draft-view space model saved)))
      (:published (notify space model id :discard :old old :new (published-view space model saved))))
    (values saved outcome)))

(defun update-draft-now (space model id patch replace)
  (let* ((content (resolve-content space (model-name model) id))
         (current (content-data content :draft t))
         (live (content-published content))
         (data (fill-slugs model (to-the-minute model (if replace patch (merge-data current patch))))))
    (cond ((same-data-p model data current) (values content :unchanged))
          ((and live (same-data-p model data live))
           (check-transition content :discard)
           (values (store (discarded content) "discard" live) :published (draft-view space model content)))
          (t
           (check-transition content :save)
           (check-content space model data :exclude-id id)
           (values (store (drafted content data) "draft" data) :saved)))))

(defun publish (space model id &optional data &key published-at)
  (let ((published-at (check-published-at published-at)))
    (multiple-value-bind (live old)
        (with-transaction (publish-now space model id data published-at))
      (notify space model id :publish :old old :new (published-view space model live))
      live)))

(defun publish-now (space model id data published-at)
  (let* ((content (resolve-content space (model-name model) id))
         (data (to-the-minute model (or data (content-data content :draft t)))))
    (check-transition content :publish)
    (check-content space model data :exclude-id id)
    (values (store (published content data :published-at published-at) "publish" data)
            (published-view space model content))))

(defun check-unreferenced (space-name model-name id verb)
  (let ((references (content-references space-name model-name id)))
    (when (plusp references)
      (fail 'conflict (format nil "This content is referenced by ~a other content~:p; remove ~:*~[~;that reference~:;those references~] before you ~a it"
                              references verb)
            :code "in_use"))))

(defun unpublish (space model id)
  (let ((space-name space)
        (model-name (model-name model)))
    (multiple-value-bind (next old)
        (with-transaction
          (let ((content (resolve-content space-name model-name id)))
            (check-transition content :unpublish)
            (check-unreferenced space-name model-name (content-id content) "unpublish")
            (let ((next (unpublished content)))
              (values (store next "unpublish" (content-draft next))
                      (published-view space model content)))))
      (notify space model id :unpublish :old old)
      next)))

(defun discard (space model id)
  (let ((space-name space)
        (model-name (model-name model)))
    (multiple-value-bind (next old)
        (with-transaction
          (let ((content (resolve-content space-name model-name id)))
            (check-transition content :discard)
            (values (store (discarded content) "discard" (content-published content))
                    (draft-view space model content))))
      (notify space model id :discard :old old :new (published-view space model next))
      next)))

(defun destroy (space model id)
  (let ((space-name space)
        (model-name (model-name model)))
    (multiple-value-bind (live draft)
        (with-transaction
          (let ((content (resolve-content space-name model-name id)))
            (check-transition content :delete)
            (check-unreferenced space-name model-name (content-id content) "delete")
            (let ((live (published-view space model content))
                  (draft (draft-view space model content)))
              (delete-content space-name id)
              (values live draft))))
      (if live
          (notify space model id :delete :old live)
          (notify space model id :discard :old draft))
      t)))

(defun draft-key (space-name model-name id)
  (resolve-model space-name model-name)
  (with-transaction
    (let* ((content (resolve-content space-name model-name id))
           (keyed (keyed content)))
      (unless (eq keyed content) (update-content keyed))
      (content-draft-key keyed))))

(defun resolve-content (space-name model-name id)
  (or (find-content space-name model-name id)
      (fail 'not-found (format nil "Content ~a does not exist" id))))

(defparameter +bulk-actions+
  '(("publish" :publish publish)
    ("unpublish" :unpublish unpublish)
    ("delete" :delete destroy)))

(defun bulk-action-function (action)
  (let ((entry (assoc action +bulk-actions+ :test #'equal)))
    (and entry (fdefinition (third entry)))))

(defun bulk-action-p (action)
  (and (bulk-action-function action) t))

(defun nothing-to-do-p (action content)
  (and content
       (let ((status (content-status content)))
         (multiple-value-bind (next allowed) (next-status status (second (assoc action +bulk-actions+ :test #'equal)))
           (or (not allowed) (equal next status))))))

(defun failure-message (condition)
  (typecase condition
    (validation-error
     (format nil "~{~a~^, ~}"
             (mapcar (lambda (e) (format nil "~a ~a" (getf e :field) (getf e :message)))
                     (validation-error-errors condition))))
    (koya-error (koya-error-message condition))
    (t (princ-to-string condition))))

(defun apply-to-each (space model ids action)
  (let ((function (bulk-action-function action))
        (model-name (model-name model))
        (done 0)
        (skipped 0)
        (failed 0)
        (message nil))
    (dolist (id ids (values done skipped failed message))
      (handler-case
          (if (nothing-to-do-p action (find-content space model-name id))
              (incf skipped)
              (progn (funcall function space model id)
                     (incf done)))
        (error (e) (incf failed) (unless message (setf message (failure-message e))))))))

(defun content-references (space model id)
  (let ((fields (reference-fields (load-schema space) model)))
    (if (zerop (hash-table-count fields))
        0
        (count-if (lambda (content) (refers-p content fields id))
                  (contents-mentioning space id :exclude-id id)))))
