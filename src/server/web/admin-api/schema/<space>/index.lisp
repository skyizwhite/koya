(defpackage #:koya-server/web/admin-api/schema/<space>/index
  (:use #:cl)
  (:import-from #:koya/core/schema #:schema->jobject #:jobject->schema)
  (:import-from #:koya/core/diff #:change->jobject)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/web/http #:read-json-body #:path-param #:param)
  (:import-from #:koya-server/usecases/schema/deploy #:space-schema #:deploy)
  (:export #:@get #:@put))
(in-package #:koya-server/web/admin-api/schema/<space>/index)

;;; One space's schema (usecases/schema/deploy).

(defun @get (params)
  (schema->jobject (space-schema (path-param params :space))))

(defun @put (params)
  "Replace the space's schema (deploy). Destructive changes need ?force=true."
  (let* ((space (path-param params :space))
         (changes (deploy space (jobject->schema (read-json-body))
                          :force (equal (param params "force") "true"))))
    (jobject "applied" (map 'vector #'change->jobject changes)
             "schema" (schema->jobject (space-schema space)))))
