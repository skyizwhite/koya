(defpackage #:koya-server/web/admin-api/contents/<space>/<model>/<id>/discard-draft
  (:use #:cl)
  (:import-from #:koya-server/web/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:discard)
  (:import-from #:koya-server/web/presenters #:admin-content->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/contents/<space>/<model>/<id>/discard-draft)

(defun @post (params)
  "Drop the draft of a published content; it goes back to status published."
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (admin-content->jobject (discard space model (path-param params :id)))))
