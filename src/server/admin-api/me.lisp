(defpackage #:koya-server/admin-api/me
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject)
  (:import-from #:lack/request #:request-env)
  (:import-from #:koya-server/lib/auth #:session-owner-p)
  (:export #:@get))
(in-package #:koya-server/admin-api/me)

(defun @get (params)
  "Who is calling: the owner through a session, or a management key (the only
other way past the admin auth middleware), plus the server version."
  (declare (ignore params))
  (let ((owner (session-owner-p (getf (request-env ningle:*request*) :lack.session))))
    (jobject "owner" (and owner t)
             "management" (not owner)
             "version" (asdf:component-version (asdf:find-system :koya-server)))))
