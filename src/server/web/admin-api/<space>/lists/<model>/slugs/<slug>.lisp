(defpackage #:koya-server/web/admin-api/<space>/lists/<model>/slugs/<slug>
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:content-by-slug)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-core/schema #:model-name)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:import-from #:koya-server/web/lib/list-content #:read-list-content #:save-list-draft #:delete-list-content)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/web/admin-api/<space>/lists/<model>/slugs/<slug>)

(defun found-id (space model params)
  (content-id (content-by-slug space (model-name model) (path-param params :slug))))

(defun @get (params)
  (with-route-model (space model :list) params
    (read-list-content space model (found-id space model params))))

(defun @patch (params)
  (with-route-model (space model :list) params
    (save-list-draft space model (found-id space model params))))

(defun @delete (params)
  (with-route-model (space model :list) params
    (delete-list-content space model (found-id space model params))))
