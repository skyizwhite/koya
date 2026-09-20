(defpackage #:koya-server/admin-api/contents/<space>/<model>/<id>/discard-draft
  (:use #:cl)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/content-service #:resolve-model #:discard)
  (:import-from #:koya-server/lib/presenter #:admin-content->jobject)
  (:export #:@post))
(in-package #:koya-server/admin-api/contents/<space>/<model>/<id>/discard-draft)

(defun @post (params)
  "Drop the draft of a published content; it goes back to status published."
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (admin-content->jobject (discard space model (path-param params :id)) model)))
