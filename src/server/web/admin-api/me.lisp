(defpackage #:koya-server/web/admin-api/me
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject #:json-null)
  (:import-from #:lack/request #:request-env)
  (:import-from #:koya-server/web/auth #:session-owner-p #:calling-space)
  (:export #:@get))
(in-package #:koya-server/web/admin-api/me)

(defun @get (params)
  "Who is calling: the owner through a session, or a management key (the only
other way past the admin auth middleware) and the space it is limited to, plus
the server version."
  (declare (ignore params))
  (let ((owner (session-owner-p (getf (request-env ningle:*request*) :lack.session))))
    (jobject "owner" (and owner t)
             "management" (not owner)
             "space" (if owner json-null (calling-space))
             ;; read at load: the image the Dockerfile saves has no ASDF systems to find
             "version" (load-time-value (asdf:component-version (asdf:find-system :koya-server))))))
