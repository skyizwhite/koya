(defpackage #:koya-server/web/admin-api/<space>/objects/<model>/index
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param #:read-json-body #:body-field #:fail-api)
  (:import-from #:koya-server/usecases/contents #:object-content #:update-object)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-object-model)
  (:export #:@get #:@patch))
(in-package #:koya-server/web/admin-api/<space>/objects/<model>/index)

(defun @get (params)
  (multiple-value-bind (space model) (resolve-object-model (path-param params :space) (path-param params :model))
    (admin-content->jobject (object-content space model))))

(defun @patch (params)
  (multiple-value-bind (space model) (resolve-object-model (path-param params :space) (path-param params :model))
    (let ((data (body-field (read-json-body) "data")))
      (unless (hash-table-p data) (fail-api 400 "bad_request" "\"data\" must be an object"))
      (admin-content->jobject (update-object space model data)))))
