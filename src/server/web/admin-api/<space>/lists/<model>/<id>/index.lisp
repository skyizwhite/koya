(defpackage #:koya-server/web/admin-api/<space>/lists/<model>/<id>/index
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/web/lib/list-content #:read-list-content #:save-list-draft #:delete-list-content)
  (:import-from #:koya-server/web/lib/route #:with-route-model)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/web/admin-api/<space>/lists/<model>/<id>/index)

(defun @get (params)
  (with-route-model (space model :list) params
    (read-list-content space model (path-param params :id))))

(defun @patch (params)
  (with-route-model (space model :list) params
    (save-list-draft space model (path-param params :id))))

(defun @delete (params)
  (with-route-model (space model :list) params
    (delete-list-content space model (path-param params :id))))
