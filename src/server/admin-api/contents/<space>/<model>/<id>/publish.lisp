(defpackage #:koya-server/admin-api/contents/<space>/<model>/<id>/publish
  (:use #:cl)
  (:import-from #:koya-server/lib/http #:path-param #:read-json-body #:body-field)
  (:import-from #:koya-server/lib/content-service #:resolve-model #:publish)
  (:import-from #:koya-server/lib/presenter #:admin-content->jobject)
  (:export #:@post))
(in-package #:koya-server/admin-api/contents/<space>/<model>/<id>/publish)

(defun @post (params)
  "Publish the draft, or {\"data\": {...}} when given. {\"publishedAt\": iso} overrides the publish date."
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (let* ((body (read-json-body))
           (data (body-field body "data")))
      (admin-content->jobject (publish space model (path-param params :id) (and (hash-table-p data) data)
                                       :published-at (body-field body "publishedAt"))
                              model))))
