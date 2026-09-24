(defpackage #:koya-server/admin-api/contents/<space>/<model>/<id>/index
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:path-param #:read-json-body #:body-field #:fail-api)
  (:import-from #:koya-server/features/contents/service #:resolve-model #:resolve-content #:update-draft #:destroy)
  (:import-from #:koya-server/features/contents/presenter #:admin-content->jobject)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/admin-api/contents/<space>/<model>/<id>/index)

(defun @get (params)
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (declare (ignore space))
    (admin-content->jobject (resolve-content (path-param params :space) (path-param params :model) (path-param params :id))
                            model)))

(defun @patch (params)
  "Save a draft: {\"data\": {...}} is merged onto the current data."
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (let ((data (body-field (read-json-body) "data")))
      (unless (hash-table-p data) (fail-api 400 "bad_request" "\"data\" must be an object"))
      (admin-content->jobject (update-draft space model (path-param params :id) data) model))))

(defun @delete (params)
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (destroy space model (path-param params :id))
    (jobject "deleted" t)))
