(defpackage #:koya-server/web/app
  (:use #:cl)
  (:import-from #:jingle
                #:make-app #:set-response-header)
  (:import-from #:ningle
                #:process-response)
  (:import-from #:ningle-fbr
                #:set-routes)
  (:import-from #:ningle-actions
                #:*actions-app*)
  (:import-from #:lack/app/file
                #:lack-app-file)
  (:import-from #:lack-mw
                #:with-args #:*trim-trailing-slash* #:*recovery*
                #:*mount* #:*session* #:*accesslog* #:make-cookie-state)
  (:import-from #:koya-server/usecases/system #:dev-mode-p #:public-url)
  (:import-from #:koya-server/web/media #:media-app)
  (:import-from #:koya-server/web/http
                #:make-json-app)
  (:import-from #:koya-server/web/middlewares
                #:*temporary-file-middleware* #:*body-limit-middleware*
                #:*cache-control-middleware* #:*delivery-cors-middleware* #:+max-body-bytes+)
  (:import-from #:smart-buffer)
  (:import-from #:koya-server/usecases/auth #:make-session-store #:+session-seconds+)
  (:import-from #:koya-server/web/auth
                #:*admin-auth-middleware* #:*actions-auth-middleware* #:*pages-auth-middleware*)
  ;; loaded for the method it adds to ports/presenters, which webhooks need
  ;; whether or not a route has loaded it
  (:import-from #:koya-server/web/presenters)
  (:import-from #:koya-server/web/document
                #:~document #:page-title)
  (:export #:app
           #:*app*
           #:*api-app*
           #:*admin-api-app*
           #:*page-app*
           #:install-routes
           #:build-app))
(in-package #:koya-server/web/app)

;;; Delivery API: /api/v1/...  (JSON, delivery key)
(defparameter *api-app* (make-json-app))

;;; Admin API: /admin/api/... (JSON, owner)
(defparameter *admin-api-app* (make-json-app))

;;; Admin UI pages: / (HTML, owner session)
(defparameter *page-app* (make-app))

(defun install-routes ()
  "Load the route files and install them. A route file is not an ASDF dependency
of this system, so loading it again leaves an edited route stale; RELOAD calls this."
  (set-routes *api-app* :system :koya-server :dir "web/api")
  (set-routes *admin-api-app* :system :koya-server :dir "web/admin-api")
  (set-routes *page-app* :system :koya-server :dir "web/pages"))

(install-routes)

(defmethod process-response :around ((app (eql *page-app*)) result)
  (if (and (consp result) (integerp (first result)))
      ;; a whole Lack response, such as a download: not a page to wrap
      (call-next-method)
      (progn
        (set-response-header :content-type "text/html; charset=utf-8")
        (call-next-method app (and result (hsx:render-to-string
                                           (hsx:hsx (~document :title (page-title) result))))))))

(defmethod process-response :around ((app (eql *actions-app*)) result)
  (set-response-header :content-type "text/html; charset=utf-8")
  (call-next-method app (and result (hsx:render-to-string (hsx:hsx result)))))

(defun session-cookie-state ()
  "The owner session cookie: HttpOnly so scripts cannot read it, SameSite=Lax so
other sites cannot post with it, Secure when the site is served over HTTPS."
  (make-cookie-state :httponly t
                     :samesite :lax
                     :expires +session-seconds+
                     :secure (and (>= (length (public-url)) 8) (string-equal "https://" (public-url) :end2 8))))

(defun build-app ()
  "The whole app: middlewares every request goes through, then each app mounted
with the middlewares it needs. The pages app answers what no mount takes."
  ;; Woo reads a whole body before the app sees it, spilling it to a file past a
  ;; megabyte; this bounds that file, for any request, signed in or not
  (setf smart-buffer:*default-disk-limit* +max-body-bytes+)
  ;; the store is the database, not the process, so a restart keeps the owner logged in
  ;; :keep-empty nil: a request that never touches its session leaves nothing behind
  (let ((session (with-args *session*
                   :store (make-session-store)
                   :state (session-cookie-state)
                   :keep-empty nil)))
    (lack:builder
     *temporary-file-middleware*
     ;; outside *RECOVERY*, so a 500 is logged and not cached like any answer
     *accesslog*
     *cache-control-middleware*
     ;; the JSON apps answer the errors of their routes themselves (web/http); an error
     ;; in a middleware stacked on them, such as a guard's, is answered here in HTML
     (with-args *recovery* :dev-mode (dev-mode-p))
     *body-limit-middleware*
     ;; CORS outside the trimming, so its redirect carries CORS headers as well
     (with-args *mount* "/api"
       (lack:builder *delivery-cors-middleware* *trim-trailing-slash* *api-app*))
     ;; files need no session: none is read for them
     (with-args *mount* "/assets" (make-instance 'lack-app-file :root #p"assets/"))
     (with-args *mount* "/media" #'media-app)
     (with-args *mount* "/admin/api"
       (lack:builder *trim-trailing-slash* session *admin-auth-middleware* *admin-api-app*))
     (with-args *mount* "/actions"
       (lack:builder session *actions-auth-middleware* *actions-app*))
     (lack:builder *trim-trailing-slash* session *pages-auth-middleware* *page-app*))))

(defvar *app* nil)

(defun app ()
  "The whole app, built on first use. Building it calls ports, so it waits for
something to ask rather than happening when this file loads, before infra may
have."
  (or *app* (setf *app* (build-app))))
