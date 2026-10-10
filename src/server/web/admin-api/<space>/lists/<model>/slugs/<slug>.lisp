(defpackage #:koya-server/web/admin-api/<space>/lists/<model>/slugs/<slug>
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/usecases/contents #:content-by-slug)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-server/usecases/schema #:resolve-list-model)
  (:import-from #:koya-server/web/lib/list-content #:read-list-content #:save-list-draft #:delete-list-content)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/web/admin-api/<space>/lists/<model>/slugs/<slug>)

(defun found-id (params)
  (resolve-list-model (path-param params :space) (path-param params :model))
  (content-id (content-by-slug (path-param params :space) (path-param params :model) (path-param params :slug))))

(defun @get (params)
  (read-list-content params (found-id params)))

(defun @patch (params)
  (save-list-draft params (found-id params)))

(defun @delete (params)
  (delete-list-content params (found-id params)))
