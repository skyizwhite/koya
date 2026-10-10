(defpackage #:koya-server/web/admin-api/<space>/lists/<model>/slugs/<slug>
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/lib/http #:path-param #:read-json-body #:body-field #:fail-api)
  (:import-from #:koya-server/usecases/contents #:update-draft #:destroy #:content-by-slug)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/web/admin-api/<space>/lists/<model>/slugs/<slug>)

(defun found (params)
  (content-by-slug (path-param params :space) (path-param params :model) (path-param params :slug)))

(defun @get (params)
  (resolve-list-model (path-param params :space) (path-param params :model))
  (admin-content->jobject (found params)))

(defun @patch (params)
  (multiple-value-bind (space model) (resolve-list-model (path-param params :space) (path-param params :model))
    (let ((data (body-field (read-json-body) "data")))
      (unless (hash-table-p data) (fail-api 400 "bad_request" "\"data\" must be an object"))
      (admin-content->jobject (update-draft space model (content-id (found params)) data)))))

(defun @delete (params)
  (multiple-value-bind (space model) (resolve-list-model (path-param params :space) (path-param params :model))
    (destroy space model (content-id (found params)))
    (jobject "deleted" t)))
