(defpackage #:koya-server/web/admin-api/contents/<space>/<model>/<id>/index
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/lib/http #:path-param #:read-json-body #:body-field #:fail-api)
  (:import-from #:koya-server/usecases/contents #:update-draft #:destroy #:resolve-content)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-model)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/web/admin-api/contents/<space>/<model>/<id>/index)

(defun @get (params)
  (resolve-model (path-param params :space) (path-param params :model))
  (admin-content->jobject (resolve-content (path-param params :space) (path-param params :model) (path-param params :id))))

(defun @patch (params)
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (let ((data (body-field (read-json-body) "data")))
      (unless (hash-table-p data) (fail-api 400 "bad_request" "\"data\" must be an object"))
      (admin-content->jobject (update-draft space model (path-param params :id) data)))))

(defun @delete (params)
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (destroy space model (path-param params :id))
    (jobject "deleted" t)))
