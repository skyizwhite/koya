(defpackage #:koya-server/web/api/v1/<space>/lists/<model>/<id>
  (:use #:cl)
  (:import-from #:koya-server/domain/query #:parse-query #:query-fields)
  (:import-from #:koya-server/web/lib/http #:path-param #:param)
  (:import-from #:koya-server/usecases/delivery #:delivered-list-content)
  (:import-from #:koya-server/web/lib/presenters #:delivered->jobject)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@get))
(in-package #:koya-server/web/api/v1/<space>/lists/<model>/<id>)

(defun @get (params)
  (with-route-model (space model :list) params
    (let ((query (parse-query params)))
      (delivered->jobject (delivered-list-content space model (path-param params :id) query
                                                  :draft-key (param params "draftKey"))
                          :fields (query-fields query)))))
