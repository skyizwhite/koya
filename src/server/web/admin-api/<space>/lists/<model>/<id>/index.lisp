(defpackage #:koya-server/web/admin-api/<space>/lists/<model>/<id>/index
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http #:path-param)
  (:import-from #:koya-server/web/lib/list-content #:read-list-content #:save-list-draft #:delete-list-content)
  (:export #:@get #:@patch #:@delete))
(in-package #:koya-server/web/admin-api/<space>/lists/<model>/<id>/index)

(defun @get (params)
  (read-list-content params (path-param params :id)))

(defun @patch (params)
  (save-list-draft params (path-param params :id)))

(defun @delete (params)
  (delete-list-content params (path-param params :id)))
