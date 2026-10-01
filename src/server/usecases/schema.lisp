(defpackage #:koya-server/usecases/schema
  (:use #:cl)
  (:import-from #:koya-core/schema #:check-schema #:check-deployable)
  (:import-from #:koya-core/diff #:diff-schemas #:destructive-changes-p)
  (:import-from #:koya-server/domain/errors #:fail #:conflict #:not-found)
  (:import-from #:koya-server/usecases/ports/spaces
                #:find-space #:load-schema #:find-model #:save-schema)
  (:import-from #:koya-server/usecases/ports/deploys
                #:list-deploys #:count-deploys #:+deploys-kept+)
  (:import-from #:koya-server/usecases/actor #:*actor*)
  (:import-from #:koya-server/usecases/spaces #:resolve-space)
  (:export #:load-schema
           #:find-model
           #:resolve-model
           #:space-schema
           #:plan
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

(defun plan (name schema)
  (check-deployable schema)
  (diff-schemas (load-schema (existing-space name)) schema))

(defun changes-of (space schema)
  (check-schema schema)
  (diff-schemas (load-schema space) schema))

(defun replace-schema (space schema &key (by *actor*))
  (let ((changes (changes-of space schema)))
    (save-schema space schema changes :by by)
    changes))

(defun deploy (name schema &key force)
  (check-deployable schema)
  (let* ((space (existing-space name))
         (changes (changes-of space schema)))
    (when (and (destructive-changes-p changes) (not force))
      (fail 'conflict "Schema deploy contains destructive changes; retry with force=true"
            :code "destructive_changes" :details changes))
    (save-schema space schema changes :by *actor*)
    changes))
