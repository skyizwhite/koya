(defpackage #:koya-server/web/admin-api/contents/<space>/<model>/<id>/discard-draft
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:discard)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/contents/<space>/<model>/<id>/discard-draft)

(defun @post (params)
  (multiple-value-bind (space model) (resolve-list-model (path-param params :space) (path-param params :model))
    (admin-content->jobject (discard space model (path-param params :id)))))
