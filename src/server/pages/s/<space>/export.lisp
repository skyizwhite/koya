(defpackage #:koya-server/pages/s/<space>/export
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/space-archive #:export-space #:archive-file-name #:archive-error)
  (:import-from #:koya-server/lib/page #:with-owner #:set-flash #:redirect-to #:space-url #:~layout)
  (:export #:@get))
(in-package #:koya-server/pages/s/<space>/export)

;;; The space as a zip download (lib/space-archive). The whole archive is built
;;; in memory before it is sent, so its size is what the process must hold.

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
              (set-flash (princ-to-string e) :error)
              (redirect-to (space-url name))))))))
