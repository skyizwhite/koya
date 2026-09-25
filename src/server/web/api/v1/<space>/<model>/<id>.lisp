(defpackage #:koya-server/web/api/v1/<space>/<model>/<id>
  (:use #:cl)
  (:import-from #:koya-server/domain/query #:parse-query #:query-fields)
  (:import-from #:koya-server/web/http #:path-param #:param)
  (:import-from #:koya-server/web/auth #:require-delivery-key)
  (:import-from #:koya-server/usecases/contents/lookup #:resolve-model)
  (:import-from #:koya-server/usecases/contents/delivery #:delivered-one)
  (:import-from #:koya-server/web/presenters #:delivered->jobject)
  (:export #:@get))
(in-package #:koya-server/web/api/v1/<space>/<model>/<id>)

(defun @get (params)
  (require-delivery-key (path-param params :space))
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (let ((query (parse-query params)))
      (delivered->jobject (delivered-one space model (path-param params :id) query
                                         :draft-key (param params "draftKey"))
                          :fields (query-fields query)))))
