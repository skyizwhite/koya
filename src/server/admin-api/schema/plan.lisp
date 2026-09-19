(defpackage #:koya-server/admin-api/schema/plan
  (:use #:cl)
  (:import-from #:koya/core/schema #:jobject->schema)
  (:import-from #:koya/core/diff #:diff-schemas #:destructive-changes-p #:change->jobject)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:read-json-body)
  (:import-from #:koya-server/db/schema-store #:load-schema)
  (:export #:@post))
(in-package #:koya-server/admin-api/schema/plan)

(defun @post (params)
  "Compute the changes a push of the given schema would apply, without applying them."
  (declare (ignore params))
  (let ((changes (diff-schemas (load-schema) (jobject->schema (read-json-body)))))
    (jobject "changes" (map 'vector #'change->jobject changes)
             "destructive" (and (destructive-changes-p changes) t))))
