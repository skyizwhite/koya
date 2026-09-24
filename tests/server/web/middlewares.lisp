(defpackage #:koya-tests/server/web/middlewares
  (:use #:cl #:rove)
  (:import-from #:koya-server/web/app #:app)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/infra/db/migrations #:migrate))
(in-package #:koya-tests/server/web/middlewares)

(setup (connect-db ":memory:") (migrate))

(teardown (disconnect-db))

(defun post-with-body-file (path)
  "POST to the app with the file at PATH as the body, open, as Woo hands over a
large one. Returns the stream."
  (with-open-file (out path :direction :output :if-exists :supersede :element-type '(unsigned-byte 8))
    (write-sequence (make-array 16 :element-type '(unsigned-byte 8) :initial-element 7) out))
  (let ((stream (open path :element-type '(unsigned-byte 8))))
    (funcall (app) (list :request-method :post :script-name "" :path-info "/health" :query-string ""
                         :server-name "localhost" :server-port 3000 :server-protocol :http/1.1
                         :request-uri "/health" :url-scheme "http" :remote-addr "127.0.0.1"
                         :headers (make-hash-table :test 'equal)
                         :content-type "application/octet-stream" :content-length 16
                         :raw-body stream))
    stream))

(deftest a-body-woo-left-on-the-disk-goes-with-the-request
  (let ((path (merge-pathnames "koya-test-body" (ensure-directories-exist smart-buffer::*temporary-directory*))))
    (let ((stream (post-with-body-file path)))
      (ng (probe-file path) "the file is gone")
      (ng (open-stream-p stream) "and closed")))
  (let ((path (uiop:tmpize-pathname (merge-pathnames "koya-test-other-body" (uiop:temporary-directory)))))
    (unwind-protect
         (let ((stream (post-with-body-file path)))
           (ok (probe-file path) "a file anywhere else is not the middleware's to delete")
           (close stream))
      (uiop:delete-file-if-exists path))))
