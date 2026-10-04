(defpackage #:koya-server/web/api/v1/<space>/lists/<model>/index
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/domain/query
                #:parse-query #:query-limit #:query-offset #:query-fields)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/delivery #:delivered-list)
  (:import-from #:koya-server/web/lib/presenters #:delivered->jobject)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model)
  (:export #:@get))
(in-package #:koya-server/web/api/v1/<space>/lists/<model>/index)

(defun @get (params)
  (multiple-value-bind (space model) (resolve-list-model (path-param params :space) (path-param params :model))
    (let ((query (parse-query params)))
      (multiple-value-bind (contents total) (delivered-list space model query)
        (jobject "contents" (map 'vector (lambda (c) (delivered->jobject c :fields (query-fields query)))
                                 contents)
                 "totalCount" total
                 "offset" (query-offset query)
                 "limit" (query-limit query))))))
