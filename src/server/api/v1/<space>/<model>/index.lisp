(defpackage #:koya-server/api/v1/<space>/<model>/index
  (:use #:cl)
  (:import-from #:koya/core/schema #:model-kind)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/domain/query #:parse-query #:query-limit #:query-offset)
  (:import-from #:koya-server/lib/http #:path-param #:param)
  (:import-from #:koya-server/lib/auth #:require-delivery-key)
  (:import-from #:koya-server/usecases/contents/lookup #:resolve-model)
  (:import-from #:koya-server/usecases/contents/delivery #:delivered-contents #:delivered-object)
  (:export #:@get))
(in-package #:koya-server/api/v1/<space>/<model>/index)

(defun @get (params)
  (require-delivery-key (path-param params :space))
  (multiple-value-bind (space model) (resolve-model (path-param params :space) (path-param params :model))
    (let ((query (parse-query params)))
      (if (eq (model-kind model) :object)
          (delivered-object space model query :draft-key (param params "draftKey"))
          (multiple-value-bind (contents total) (delivered-contents space model query)
            (jobject "contents" contents
                     "totalCount" total
                     "offset" (query-offset query)
                     "limit" (query-limit query)))))))
