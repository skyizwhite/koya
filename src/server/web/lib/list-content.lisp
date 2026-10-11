(defpackage #:koya-server/web/lib/list-content
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-core/schema #:model-name)
  (:import-from #:koya-server/web/lib/http #:read-json-body #:body-data)
  (:import-from #:koya-server/usecases/contents #:update-draft #:destroy #:resolve-content)
  (:import-from #:koya-server/web/lib/presenters #:admin-content->jobject)
  (:export #:read-list-content #:save-list-draft #:delete-list-content))
(in-package #:koya-server/web/lib/list-content)

(defun read-list-content (space model id)
  (admin-content->jobject (resolve-content space (model-name model) id)))

(defun save-list-draft (space model id)
  (admin-content->jobject (update-draft space model id (body-data (read-json-body)))))

(defun delete-list-content (space model id)
  (destroy space model id)
  (jobject "deleted" t))
