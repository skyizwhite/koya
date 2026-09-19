(defpackage #:koya-server/pages/logout
  (:use #:cl)
  (:import-from #:koya-server/lib/auth #:session-logout)
  (:import-from #:koya-server/lib/page #:with-owner-post #:redirect-to)
  (:export #:@post))
(in-package #:koya-server/pages/logout)

(defun @post (params)
  (declare (ignore params))
  (with-owner-post
    (session-logout)
    (redirect-to "/login")))
