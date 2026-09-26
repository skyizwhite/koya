(defpackage #:koya-server/web/admin-api/keys/<space>/<id>
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/http #:path-param)
  (:import-from #:koya-server/usecases/keys #:delete-delivery-key)
  (:export #:@delete))
(in-package #:koya-server/web/admin-api/keys/<space>/<id>)

(defun @delete (params)
  (delete-delivery-key (path-param params :space) (path-param params :id))
  (jobject "deleted" t))
