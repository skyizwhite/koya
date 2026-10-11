(defpackage #:koya-server/web/admin-api/<space>/lists/<model>/<id>/publish
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param #:read-json-body #:body-field #:body-data)
  (:import-from #:koya-server/usecases/contents #:publish)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/<space>/lists/<model>/<id>/publish)

(defun @post (params)
  (with-route-model (space model :list) params
    (let ((body (read-json-body)))
      (admin-content->jobject (publish space model (path-param params :id) :data (body-data body :nullable t)
                                       :published-at (body-field body "publishedAt"))))))
