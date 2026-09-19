(defpackage #:koya-server/admin-api/me
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:export #:@get))
(in-package #:koya-server/admin-api/me)

(defun @get (params)
  (declare (ignore params))
  (jobject "owner" t "version" (asdf:component-version (asdf:find-system :koya-server))))
