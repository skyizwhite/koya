(defpackage #:koya-server/usecases/schema
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:check-schema #:check-deployable #:schema-model #:model-field #:make-model
                #:field-name #:field-option #:model-kind #:field-fields #:field-row-kinds
                #:field-path-parts #:custom-field-name #:custom-field-fields)
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
           #:resolve-list-model
           #:resolve-object-model
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

(defun resolve-list-model (space-name model-name)
  (multiple-value-bind (space model) (resolve-model space-name model-name)
    (when (eq (model-kind model) :object)
      (fail 'not-found (format nil "~a is an object model; its content is reached through the model, not an id" model-name)))
    (values space model)))

(defun resolve-object-model (space-name model-name)
  (multiple-value-bind (space model) (resolve-model space-name model-name)
    (unless (eq (model-kind model) :object)
      (fail 'not-found (format nil "~a is a list model; a content of it is reached through its id" model-name)))
    (values space model)))

(defun space-schema (name)
  (load-schema (existing-space name)))

(defun made-anew-p (changes model)
  (find-if (lambda (c) (and (eq (getf c :op) :change-kind) (equal (getf c :model) model))) changes))

(defun outer-name (path)
  (values (field-path-parts path)))

(defun inner-fields (field kind)
  (if kind
      (let ((custom (find kind (field-row-kinds field) :key #'custom-field-name :test #'string=)))
        (and custom (custom-field-fields custom)))
      (field-fields field)))

(defun changed-field (schema change)
  (multiple-value-bind (outer kind inner) (field-path-parts (getf change :field))
    (let ((field (model-field (schema-model schema (getf change :model)) outer)))
      (if inner
          (find inner (inner-fields field kind) :key #'field-name :test #'string=)
          field))))

(defun checked-change-p (change schema changes)
  (and (not (made-anew-p changes (getf change :model)))
       (or (tightened-change-p change)
           (and (eq (getf change :op) :add-field)
                (field-option (changed-field schema change) :required)))))

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

(defun gone-inside (changes model outer)
  (loop :for change :in changes
        :when (and (getf change :field) (member (getf change :op) '(:remove-field :change-field-type))
                   (equal (getf change :model) model))
          :append (multiple-value-bind (name kind inner) (field-path-parts (getf change :field))
                    (and inner (string= name outer) (list (cons kind inner))))))

(defun without-gone (object kind gone)
  (let ((kept (jobject)))
    (maphash (lambda (k v)
               (unless (find-if (lambda (g) (and (equal (car g) kind) (string= (cdr g) k))) gone)
                 (setf (gethash k kept) v)))
             object)
    kept))

(defun as-deployed (value gone)
  (cond ((null gone) value)
        ((hash-table-p value) (without-gone value nil gone))
        ((and (vectorp value) (not (stringp value)))
         (map 'vector (lambda (row)
                        (if (hash-table-p row) (without-gone row (gethash "fieldId" row) gone) row))
              value))
        (t value)))

(defun value-misfits (contents field key &optional gone)
  (let ((check (make-model "check" :list (list field)))
        (name (field-name field)))
    (loop :for content :in contents
          :append (loop :for (version data) :in (versions content)
                        :append (let ((one (jobject)))
                                  (multiple-value-bind (value found) (gethash key data)
                                    (when found (setf (gethash name one) (as-deployed value gone))))
                                  (mapcar (lambda (e) (misfit content version (getf e :field) (getf e :message)))
                                          (validate-content check one)))))))

(defun object-misfits (content version check name object path)
  (let ((one (jobject)))
    (multiple-value-bind (value found) (gethash name object)
      (when found (setf (gethash name one) value)))
    (mapcar (lambda (e) (misfit content version (format nil "~a.~a" path (getf e :field)) (getf e :message)))
            (validate-content check one))))

(defun inner-misfits (contents outer kind inner key gone)
  (let ((check (make-model "check" :list (list inner)))
        (name (field-name inner)))
    (loop :for content :in contents
          :append (loop :for (version data) :in (versions content)
                        :for value := (as-deployed (gethash key data) gone)
                        :append (cond ((and (null kind) (hash-table-p value))
                                       (object-misfits content version check name value (field-name outer)))
                                      ((and kind (vectorp value) (not (stringp value)))
                                       (loop :for row :across value
                                             :for index :from 0
                                             :when (and (hash-table-p row) (equal (gethash "fieldId" row) kind))
                                               :append (object-misfits content version check name row
                                                                       (format nil "~a[~a]" (field-name outer) index))))
                                      (t '()))))))

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
                         (outer (outer-name (getf change :field)))
                         (field (model-field (schema-model schema model) outer))
                         (stored-model (stored-name changes :rename-model model))
                         (key (stored-name changes :rename-field model outer))
                         (of-model (remove-if-not (lambda (c) (equal (content-model c) stored-model)) contents))
                         (gone (gone-inside changes model outer))
                         (misfits (if (nth-value 2 (field-path-parts (getf change :field)))
                                      (inner-misfits of-model field (nth-value 1 (field-path-parts (getf change :field)))
                                                     (changed-field schema change) key gone)
                                      (append (value-misfits of-model field key gone)
                                              (and (field-option field :unique) (unique-misfits of-model field key))))))
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
