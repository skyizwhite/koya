(defpackage #:koya-server/web/admin-api/<space>/objects/<model>/unpublish
  (:use #:cl)
  (:import-from #:koya-server/usecases/contents #:unpublish #:object-content)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/<space>/objects/<model>/unpublish)

(defun @post (params)
  (with-route-model (space model :object) params
    (admin-content->jobject (unpublish space model (content-id (object-content space model))))))
