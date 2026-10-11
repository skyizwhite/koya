(defpackage #:koya-server/web/admin-api/<space>/objects/<model>/index
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:read-json-body #:body-data)
  (:import-from #:koya-server/usecases/contents #:object-content #:update-object)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@get #:@patch))
(in-package #:koya-server/web/admin-api/<space>/objects/<model>/index)

(defun @get (params)
  (with-route-model (space model :object) params
    (admin-content->jobject (object-content space model))))

(defun @patch (params)
  (with-route-model (space model :object) params
    (admin-content->jobject (update-object space model (body-data (read-json-body))))))
