(defpackage #:koya-server/web/admin-api/contents/<space>/<model>/<id>/unpublish
  (:use #:cl)
  (:import-from #:koya-server/web/http #:path-param)
  (:import-from #:koya-server/usecases/contents/write #:unpublish)
  (:import-from #:koya-server/usecases/contents/lookup #:resolve-model)
  (:import-from #:koya-server/web/presenters #:admin-content->jobject)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/contents/<space>/<model>/<id>/unpublish)

(defun @post (params)
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (admin-content->jobject (unpublish space model (path-param params :id)))))
