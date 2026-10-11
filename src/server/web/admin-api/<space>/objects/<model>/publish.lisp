(defpackage #:koya-server/web/admin-api/<space>/objects/<model>/publish
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:read-json-body #:body-field #:body-data)
  (:import-from #:koya-server/usecases/contents #:publish-object)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/<space>/objects/<model>/publish)

(defun @post (params)
  (with-route-model (space model :object) params
    (let ((body (read-json-body)))
      (admin-content->jobject (publish-object space model :data (body-data body :nullable t)
                                              :published-at (body-field body "publishedAt"))))))
