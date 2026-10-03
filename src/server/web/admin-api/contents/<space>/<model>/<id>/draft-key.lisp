(defpackage #:koya-server/web/admin-api/contents/<space>/<model>/<id>/draft-key
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:draft-key)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model)
  (:export #:@post))
(in-package #:koya-server/web/admin-api/contents/<space>/<model>/<id>/draft-key)

(defun @post (params)
  (resolve-list-model (path-param params :space) (path-param params :model))
  (jobject "draftKey" (draft-key (path-param params :space) (path-param params :model) (path-param params :id))))
