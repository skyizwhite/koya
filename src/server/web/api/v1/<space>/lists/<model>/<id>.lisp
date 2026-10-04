(defpackage #:koya-server/web/api/v1/<space>/lists/<model>/<id>
  (:use #:cl)
  (:import-from #:koya-server/domain/query #:parse-query #:query-fields)
  (:import-from #:koya-server/web/lib/http #:path-param #:param)
  (:import-from #:koya-server/usecases/delivery #:delivered-list-content)
  (:import-from #:koya-server/web/lib/presenters #:delivered->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model)
  (:export #:@get))
(in-package #:koya-server/web/api/v1/<space>/lists/<model>/<id>)

(defun @get (params)
  (multiple-value-bind (space model) (resolve-list-model (path-param params :space) (path-param params :model))
    (let ((query (parse-query params)))
      (delivered->jobject (delivered-list-content space model (path-param params :id) query
                                                  :draft-key (param params "draftKey"))
                          :fields (query-fields query)))))
