(defpackage #:koya-server/admin-api/schema/index
  (:use #:cl)
  (:import-from #:koya/core/schema #:schema->jobject #:jobject->schema)
  (:import-from #:koya/core/diff #:diff-schemas #:destructive-changes-p #:change->jobject)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:read-json-body #:query-param #:fail-api)
  (:import-from #:koya-server/db/schema-store #:load-schema #:save-schema)
  (:export #:@get #:@put))
(in-package #:koya-server/admin-api/schema/index)

(defun @get (params)
  (declare (ignore params))
  (schema->jobject (load-schema)))

(defun changes->jarray (changes)
  (map 'vector #'change->jobject changes))

(defun @put (params)
  "Replace the stored schema (push). Destructive changes need ?force=true."
  (let* ((new (jobject->schema (read-json-body)))
         (changes (diff-schemas (load-schema) new))
         (force (equal (query-param params "force") "true")))
    (when (and (destructive-changes-p changes) (not force))
      (fail-api 409 "destructive_changes" "Schema push contains destructive changes; retry with force=true"
                (changes->jarray changes)))
    (save-schema new)
    (jobject "applied" (changes->jarray changes)
             "schema" (schema->jobject (load-schema)))))
