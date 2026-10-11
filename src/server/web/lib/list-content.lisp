(defpackage #:koya-server/web/lib/list-content
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/lib/http #:path-param #:read-json-body #:body-data)
  (:import-from #:koya-server/usecases/contents #:update-draft #:destroy #:resolve-content)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:read-list-content #:save-list-draft #:delete-list-content))
(in-package #:koya-server/web/lib/list-content)

(defun read-list-content (params id)
  (with-route-model (space model :list) params
    (admin-content->jobject (resolve-content (path-param params :space) (path-param params :model) id))))

(defun save-list-draft (params id)
  (with-route-model (space model :list) params
    (admin-content->jobject (update-draft space model id (body-data (read-json-body))))))

(defun delete-list-content (params id)
  (with-route-model (space model :list) params
    (destroy space model id)
    (jobject "deleted" t)))
