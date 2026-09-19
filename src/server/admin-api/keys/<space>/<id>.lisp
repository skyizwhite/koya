(defpackage #:koya-server/admin-api/keys/<space>/<id>
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/db/api-keys #:delete-api-key)
  (:export #:@delete))
(in-package #:koya-server/admin-api/keys/<space>/<id>)

(defun @delete (params)
  (delete-api-key (path-param params :space) (path-param params :id))
  (jobject "deleted" t))
