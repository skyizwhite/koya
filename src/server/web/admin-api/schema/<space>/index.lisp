(defpackage #:koya-server/web/admin-api/schema/<space>/index
  (:use #:cl)
  (:import-from #:koya-core/schema #:schema->jobject #:jobject->schema)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/domain/errors #:conflict #:koya-error-code #:koya-error-message #:koya-error-details)
  (:import-from #:koya-server/web/http #:read-json-body #:path-param #:param #:fail-api)
  (:import-from #:koya-server/web/presenters #:changes->jarray)
  (:import-from #:koya-server/usecases/schema/deploy #:space-schema #:deploy)
  (:export #:@get #:@put))
(in-package #:koya-server/web/admin-api/schema/<space>/index)

;;; One space's schema (usecases/schema/deploy).

(defun @get (params)
  (schema->jobject (space-schema (path-param params :space))))

(defun @put (params)
  "Replace the space's schema (deploy). Destructive changes need ?force=true."
  (let* ((space (path-param params :space))
         (changes (handler-case (deploy space (jobject->schema (read-json-body))
                                        :force (equal (param params "force") "true"))
                    (conflict (e)
                      ;; the changes a refused deploy would make, for the caller to look over
                      (if (equal (koya-error-code e) "destructive_changes")
                          (fail-api 409 (koya-error-code e) (koya-error-message e)
                                    (changes->jarray (koya-error-details e)))
                          (error e))))))
    (jobject "applied" (changes->jarray changes)
             "schema" (schema->jobject (space-schema space)))))
