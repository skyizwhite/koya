(defpackage #:koya-server/web/admin-api/me
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject)
  (:import-from #:koya-server/web/lib/auth #:calling-space)
  (:export #:@get))
(in-package #:koya-server/web/admin-api/me)

(defun @get (params)
  (declare (ignore params))
  (jobject "space" (calling-space)
           "version" (load-time-value (asdf:component-version (asdf:find-system :koya-server)))))
