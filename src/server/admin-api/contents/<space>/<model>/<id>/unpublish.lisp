(defpackage #:koya-server/admin-api/contents/<space>/<model>/<id>/unpublish
  (:use #:cl)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/features/contents/service #:resolve-model #:unpublish)
  (:import-from #:koya-server/features/contents/presenter #:admin-content->jobject)
  (:export #:@post))
(in-package #:koya-server/admin-api/contents/<space>/<model>/<id>/unpublish)

(defun @post (params)
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (admin-content->jobject (unpublish space model (path-param params :id)) model)))
