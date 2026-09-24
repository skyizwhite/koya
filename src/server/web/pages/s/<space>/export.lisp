(defpackage #:koya-server/web/pages/s/<space>/export
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:find-space)
  (:import-from #:koya-server/web/http #:path-param #:redirect-to)
  (:import-from #:koya-server/usecases/spaces/archive
                #:export-space #:archive-file-name #:archive-error)
  (:import-from #:koya-server/web/auth #:with-owner)
  (:import-from #:koya-server/web/urls #:space-url)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/toast #:set-toast)
  (:export #:@get))
(in-package #:koya-server/web/pages/s/<space>/export)

;;; The space as a zip download (usecases/spaces/archive). The whole archive is
;;; built in memory before it is sent, so its size is what the process must hold.
;;;
;;; The link to it carries no download attribute: Content-Disposition makes the
;;; zip a download on its own, and a failure -- a redirect to the space page with
;;; the toast, or to the login page -- has to be shown, not saved as a file.

(defun @get (params)
  (with-owner
    (let ((name (path-param params :space)))
      (if (null (find-space name))
          (progn (set-response-status 404)
                 (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
          (handler-case
              (let ((octets (export-space name)))
                (list 200 (list :content-type "application/zip"
                                :content-length (length octets)
                                :content-disposition (format nil "attachment; filename=\"~a\"" (archive-file-name name)))
                      octets))
            (archive-error (e)
              (set-toast (princ-to-string e) :error)
              (redirect-to (space-url name))))))))
