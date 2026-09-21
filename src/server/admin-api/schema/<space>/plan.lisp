(defpackage #:koya-server/admin-api/schema/<space>/plan
  (:use #:cl)
  (:import-from #:koya/core/schema #:jobject->schema)
  (:import-from #:koya/core/diff #:diff-schemas #:destructive-changes-p #:change->jobject)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:read-json-body #:path-param #:fail-api)
  (:import-from #:koya-server/db/schema-store #:load-schema #:find-space)
  (:export #:@post))
(in-package #:koya-server/admin-api/schema/<space>/plan)

(defun @post (params)
  "What a deploy of the posted schema would change in this space. Changes nothing."
  (let* ((name (path-param params :space))
         (space (or (find-space name)
                    (fail-api 404 "not_found" (format nil "Space ~a does not exist; create it in the admin UI" name))))
         (changes (diff-schemas (load-schema space) (jobject->schema (read-json-body)))))
    (jobject "changes" (map 'vector #'change->jobject changes)
             "destructive" (destructive-changes-p changes))))
