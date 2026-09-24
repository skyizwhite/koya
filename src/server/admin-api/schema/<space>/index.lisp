(defpackage #:koya-server/admin-api/schema/<space>/index
  (:use #:cl)
  (:import-from #:koya/core/schema #:schema->jobject #:jobject->schema)
  (:import-from #:koya/core/diff #:diff-schemas #:destructive-changes-p #:change->jobject)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:read-json-body #:path-param #:param #:fail-api)
  (:import-from #:koya-server/lib/auth #:calling-identity)
  (:import-from #:koya-server/db/schema-store #:load-schema #:save-schema #:find-space)
  (:export #:@get #:@put))
(in-package #:koya-server/admin-api/schema/<space>/index)

;;; One space's schema. The space itself is made in the admin UI, so a deploy to a
;;; name that does not exist is an error and never creates one: a typo in
;;; KOYA_SPACE must not quietly grow a second, empty space.

(defun space-of (params)
  (let ((name (path-param params :space)))
    (or (find-space name)
        (fail-api 404 "not_found" (format nil "Space ~a does not exist; create it in the admin UI" name)))))

(defun @get (params)
  (schema->jobject (load-schema (space-of params))))

(defun changes->jarray (changes)
  (map 'vector #'change->jobject changes))

(defun @put (params)
  "Replace the space's schema (deploy). Destructive changes need ?force=true."
  (let* ((space (space-of params))
         (new (jobject->schema (read-json-body)))
         (changes (diff-schemas (load-schema space) new))
         (force (equal (param params "force") "true")))
    (when (and (destructive-changes-p changes) (not force))
      (fail-api 409 "destructive_changes" "Schema deploy contains destructive changes; retry with force=true"
                (changes->jarray changes)))
    (save-schema space new :by (calling-identity))
    (jobject "applied" (changes->jarray changes)
             "schema" (schema->jobject (load-schema space)))))
