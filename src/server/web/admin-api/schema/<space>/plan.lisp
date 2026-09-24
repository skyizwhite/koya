(defpackage #:koya-server/web/admin-api/schema/<space>/plan
  (:use #:cl)
  (:import-from #:koya/core/schema #:jobject->schema)
  (:import-from #:koya/core/diff #:destructive-changes-p #:change->jobject)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/web/http #:read-json-body #:path-param)
  (:import-from #:koya-server/usecases/schema/deploy #:plan)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/schema/<space>/plan)

(defun @post (params)
  "What a deploy of the posted schema would change in this space. Changes nothing."
  (let ((changes (plan (path-param params :space) (jobject->schema (read-json-body)))))
    (jobject "changes" (map 'vector #'change->jobject changes)
             "destructive" (destructive-changes-p changes))))
