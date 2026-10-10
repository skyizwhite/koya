(defpackage #:koya-server/web/pages/s/<space>/export
  (:use #:cl #:hsx)
  (:import-from #:koya-server/usecases/spaces #:find-space)
  (:import-from #:koya-server/web/lib/http #:path-param #:redirect-to)
  (:import-from #:koya-server/usecases/archive
                #:export-space #:archive-file-name #:archive-error)
  (:import-from #:koya-server/web/lib/urls #:space-url)
  (:import-from #:koya-server/web/ui/layout #:~missing)
  (:import-from #:koya-server/web/ui/toast #:set-toast)
  (:import-from #:koya-server/web/lib/middlewares #:+temporary-file-header+)
  (:export #:@get))
(in-package #:koya-server/web/pages/s/<space>/export)

(defun @get (params)
  (let ((name (path-param params :space)))
    (if (null (find-space name))
        (hsx (~missing :what "Space"))
        (handler-case
            (list 200 (list :content-type "application/zip"
                            :content-disposition (format nil "attachment; filename=\"~a\"" (archive-file-name name))
                            +temporary-file-header+ "1")
                  (export-space name))
          (archive-error (e)
            (set-toast (princ-to-string e) :error)
            (redirect-to (space-url name)))))))
