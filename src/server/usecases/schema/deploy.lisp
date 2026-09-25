(defpackage #:koya-server/usecases/schema/deploy
  (:use #:cl)
  (:import-from #:koya/core/diff
                #:diff-schemas #:destructive-changes-p)
  (:import-from #:koya-server/domain/errors
                #:fail #:conflict #:not-found)
  (:import-from #:koya-server/usecases/ports/spaces
                #:find-space #:load-schema #:save-schema #:list-deploys #:count-deploys #:+deploys-kept+)
  (:import-from #:koya-server/usecases/actor
                #:*actor*)
  (:export #:space-schema
           #:plan
           #:deploy
           #:list-deploys
           #:count-deploys
           #:+deploys-kept+))
(in-package #:koya-server/usecases/schema/deploy)

;;; A site deploys its schema to one space. The space itself is made in the admin
;;; UI, so a deploy to a name that does not exist is an error and never creates
;;; one: a typo in KOYA_SPACE must not quietly grow a second, empty space.

(defun existing-space (name)
  (or (find-space name)
      (fail 'not-found (format nil "Space ~a does not exist; create it in the admin UI" name))))

(defun space-schema (name)
  "The schema deployed to space NAME."
  (load-schema (existing-space name)))

(defun plan (name schema)
  "The changes a deploy of SCHEMA to space NAME would make. Changes nothing."
  (diff-schemas (load-schema (existing-space name)) schema))

(defun deploy (name schema &key force)
  "Make SCHEMA the schema of space NAME, and return the changes that took. A
deploy that would destroy something signals a CONFLICT coded
destructive_changes, whose details are the changes, unless FORCE."
  (let* ((space (existing-space name))
         (changes (diff-schemas (load-schema space) schema)))
    (when (and (destructive-changes-p changes) (not force))
      (fail 'conflict "Schema deploy contains destructive changes; retry with force=true"
            :code "destructive_changes" :details changes))
    (save-schema space schema :by *actor*)
    changes))
