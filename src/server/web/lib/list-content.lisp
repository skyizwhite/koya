(defpackage #:koya-server/web/lib/list-content
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/lib/http #:path-param #:read-json-body #:body-field #:fail-api)
  (:import-from #:koya-server/usecases/contents #:update-draft #:destroy #:resolve-content)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model)
  (:export #:read-list-content #:save-list-draft #:delete-list-content))
(in-package #:koya-server/web/lib/list-content)

(defun read-list-content (params id)
  (resolve-list-model (path-param params :space) (path-param params :model))
  (admin-content->jobject (resolve-content (path-param params :space) (path-param params :model) id)))

(defun save-list-draft (params id)
  (multiple-value-bind (space model) (resolve-list-model (path-param params :space) (path-param params :model))
    (let ((data (body-field (read-json-body) "data")))
      (unless (hash-table-p data) (fail-api 400 "bad_request" "\"data\" must be an object"))
      (admin-content->jobject (update-draft space model id data)))))

(defun delete-list-content (params id)
  (multiple-value-bind (space model) (resolve-list-model (path-param params :space) (path-param params :model))
    (destroy space model id)
    (jobject "deleted" t)))
