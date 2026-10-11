(defpackage #:koya-server/web/admin-api/<space>/lists/<model>/<id>/discard-draft
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:discard)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/<space>/lists/<model>/<id>/discard-draft)

(defun @post (params)
  (with-route-model (space model :list) params
    (admin-content->jobject (discard space model (path-param params :id)))))
