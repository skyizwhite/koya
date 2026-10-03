(defpackage #:koya-server/web/admin-api/contents/<space>/<model>/discard-draft
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:discard #:object-content)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-object-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/contents/<space>/<model>/discard-draft)

(defun @post (params)
  (multiple-value-bind (space model) (resolve-object-model (path-param params :space) (path-param params :model))
    (admin-content->jobject (discard space model (content-id (object-content space model))))))
