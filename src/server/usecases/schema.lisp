(defpackage #:koya-server/usecases/schema
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:check-schema #:check-deployable #:schema-model #:model-field #:make-model
                #:field-name #:field-option)
  (:import-from #:koya-core/validate #:validate-content #:blank-value-p)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/usecases/ports/contents #:space-contents)
  (:import-from #:koya-server/domain/content #:content-id #:content-model #:content-published #:content-draft)
  (:import-from #:koya-server/domain/deploy #:changes-by-served-model)
  (:import-from #:koya-server/usecases/webhooks #:notify-webhooks)
  (:import-from #:koya-core/diff #:diff-schemas #:destructive-changes-p #:tightened-change-p)
  (:import-from #:koya-server/domain/errors #:fail #:conflict #:not-found)
  (:import-from #:koya-server/usecases/ports/spaces
                #:find-space #:load-schema #:find-model #:save-schema #:space-webhook-secret)
  (:import-from #:koya-server/usecases/ports/deploys
                #:list-deploys #:count-deploys #:+deploys-kept+)
  (:import-from #:koya-server/usecases/actor #:*actor*)
  (:import-from #:koya-server/usecases/spaces #:resolve-space)
  (:export #:load-schema
           #:find-model
           #:resolve-model
           #:space-schema
           #:plan
           #:unique-misfits
           #:deploy
           #:replace-schema
           #:list-deploys
           #:count-deploys
           #:+deploys-kept+))
(in-package #:koya-server/usecases/schema)

(defun existing-space (name)
  (or (find-space name)
      (fail 'not-found (format nil "Space ~a does not exist; create it in the admin UI" name))))

(defun resolve-model (space-name model-name)
  (let* ((space (resolve-space space-name))
         (model (or (find-model space model-name)
                    (fail 'not-found (format nil "Model ~a does not exist" model-name)))))
    (values space model)))

(defun space-schema (name)
  (load-schema (existing-space name)))

(defun made-anew-p (changes model)
  (find-if (lambda (c) (and (eq (getf c :op) :change-kind) (equal (getf c :model) model))) changes))

(defun checked-change-p (change schema changes)
  (and (not (made-anew-p changes (getf change :model)))
       (or (tightened-change-p change)
           (and (eq (getf change :op) :add-field)
                (field-option (model-field (schema-model schema (getf change :model)) (getf change :field))
                              :required)))))

(defun stored-name (changes op model &optional field)
  (let ((rename (find-if (lambda (c) (and (eq (getf c :op) op) (equal (getf c :model) model)
                                          (or (null field) (equal (getf c :field) field))))
                         changes)))
    (if rename (getf rename :from) (or field model))))

(defun versions (content)
  (remove nil (list (and (content-published content) (list "published" (content-published content)))
                    (and (content-draft content) (list "draft" (content-draft content))))))

(defun misfit (content version field message)
  (list :id (content-id content) :field field :version version :message message))

(defun value-misfits (contents field key)
  (let ((check (make-model "check" :list (list field)))
        (name (field-name field)))
    (loop :for content :in contents
          :append (loop :for (version data) :in (versions content)
                        :append (let ((one (jobject)))
                                  (multiple-value-bind (value found) (gethash key data)
                                    (when found (setf (gethash name one) value)))
                                  (mapcar (lambda (e) (misfit content version name (getf e :message)))
                                          (validate-content check one)))))))

(defun unique-misfits (contents field key)
  (let ((owners (make-hash-table :test 'equal))
        (name (field-name field)))
    (dolist (content contents)
      (loop :for (version data) :in (versions content)
            :for value := (gethash key data)
            :unless (blank-value-p value)
              :do (pushnew (content-id content) (gethash value owners) :test #'equal)))
    (loop :for content :in contents
          :append (loop :for (version data) :in (versions content)
                        :for value := (gethash key data)
                        :when (and (not (blank-value-p value)) (rest (gethash value owners)))
                          :collect (misfit content version name "must be unique")))))

(defun with-misfits (space schema changes)
  (let ((contents (space-contents space)))
    (mapcar (lambda (change)
              (if (checked-change-p change schema changes)
                  (let* ((model (getf change :model))
                         (field (model-field (schema-model schema model) (getf change :field)))
                         (stored-model (stored-name changes :rename-model model))
                         (key (stored-name changes :rename-field model (getf change :field)))
                         (of-model (remove-if-not (lambda (c) (equal (content-model c) stored-model)) contents))
                         (misfits (append (value-misfits of-model field key)
                                          (and (field-option field :unique) (unique-misfits of-model field key)))))
                    (if misfits (append change (list :misfits misfits)) change))
                  change))
            changes)))

(defun plan (name schema)
  (check-deployable schema)
  (let ((space (existing-space name)))
    (with-misfits space schema (diff-schemas (load-schema space) schema))))

(defun changes-of (space schema)
  (check-schema schema)
  (diff-schemas (load-schema space) schema))

(defun replace-schema (space schema &key (by *actor*))
  (let ((changes (changes-of space schema)))
    (save-schema space schema changes :by by)
    changes))

(defun notify-deploy (space before changes)
  (loop :for (model-name . model-changes) :in (changes-by-served-model changes)
        :for model := (or (find-model space model-name) (schema-model before model-name))
        :do (notify-webhooks space model nil :deploy :changes model-changes
                                                     :secret (space-webhook-secret space))))

(defun deploy (name schema &key force)
  (check-deployable schema)
  (let* ((space (existing-space name))
         (before (load-schema space))
         (changes (with-misfits space schema (changes-of space schema))))
    (when (some (lambda (change) (getf change :misfits)) changes)
      (fail 'conflict "Some contents do not fit the new schema; change them before deploying it"
            :code "contents_do_not_fit" :details changes))
    (when (and (destructive-changes-p changes) (not force))
      (fail 'conflict "Schema deploy contains destructive changes; retry with force=true"
            :code "destructive_changes" :details changes))
    (save-schema space schema changes :by *actor*)
    (notify-deploy space before changes)
    changes))
