(defpackage #:koya-server/pages/import
  (:use #:cl #:hsx)
  (:import-from #:lack/request #:request-env)
  (:import-from #:koya-server/lib/auth #:calling-identity)
  (:import-from #:koya-server/lib/space-archive #:import-space #:+max-archive-bytes+)
  (:import-from #:koya-server/lib/page #:with-owner-post #:set-flash #:space-url)
  (:export #:@post))
(in-package #:koya-server/pages/import)

;;; A space archive from Export, made into a space again (lib/space-archive).
;;;
;;; The form on the spaces page sends the file itself as an application/zip body
;;; (koya-editor.js), not as a multipart form, which lack would hold in memory
;;; several times over. *BODY-LIMIT-MIDDLEWARE* sets that body aside unread; it
;;; is copied to a file here, once the owner is known, and read from there. The
;;; answer is where to go next, as text: the flash waits there.

(defun copy-to-file (in path)
  "Copy IN to PATH, refusing more than the import limit: a chunked body has no
Content-Length for the middleware to check."
  (with-open-file (out path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
    (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8))))
      (loop :for n := (read-sequence buffer in)
            :for total := n :then (+ total n)
            :while (plusp n)
            :do (when (> total +max-archive-bytes+)
                  (error "The archive is larger than ~a MB" (floor +max-archive-bytes+ (* 1024 1024))))
                (write-sequence buffer out :end n)))))

(defun import-archive (body)
  "The location to go to after importing the archive in the stream BODY."
  (uiop:with-temporary-file (:pathname path :type "zip")
    ;; every condition: a bad archive can fail in the zip reader, the schema
    ;; check or the database, and each one's message is what the owner needs
    (handler-case
        (progn
          (copy-to-file body path)
          (let ((space (import-space path :by (calling-identity))))
            (set-flash (format nil "Space ~a imported." space))
            (space-url space)))
      (error (e)
        (set-flash (format nil "Import failed: ~a" e) :error)
        "/"))))

(defun @post (params)
  (declare (ignore params))
  (with-owner-post
    (let ((body (getf (request-env ningle:*request*) :koya.import-body)))
      (list 200 (list :content-type "text/plain; charset=utf-8")
            (list (if body
                      (import-archive body)
                      (progn (set-flash "Choose an archive to import." :error) "/")))))))
