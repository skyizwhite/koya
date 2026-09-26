(defpackage #:koya-server/web/app
  (:use #:cl)
  (:import-from #:jingle
                #:make-app #:install-middleware #:clear-middlewares #:static-path #:configure #:set-response-header)
  (:import-from #:ningle
                #:process-response)
  (:import-from #:ningle-fbr
                #:set-routes)
  (:import-from #:ningle-actions
                #:*actions-app* #:*actions-middleware*)
  (:import-from #:lack-mw
                #:with-args #:*trim-trailing-slash* #:*temporary-file*
                #:*mount* #:*session* #:*accesslog* #:make-cookie-state)
  (:import-from #:clack-errors
                #:*clack-error-middleware*)
  (:import-from #:koya-server/usecases/system #:dev-mode-p #:public-url)
  (:import-from #:koya-server/web/media #:*media-middleware*)
  (:import-from #:koya-server/web/http
                #:make-json-app)
  (:import-from #:koya-server/web/middlewares
                #:*body-limit-middleware*
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
  (clear-middlewares *page-app*)
  ;; Woo reads a whole body before the app sees it, spilling it to a file past a
  ;; megabyte; this bounds that file, for any request, signed in or not
  (setf smart-buffer:*default-disk-limit* +max-body-bytes+)
  (install-middleware *page-app* *temporary-file*)
  (install-middleware *page-app* (with-args *clack-error-middleware* :debug (dev-mode-p)))
  (install-middleware *page-app* *body-limit-middleware*)
  (install-middleware *page-app* *cache-control-middleware*)
  (install-middleware *page-app* *accesslog*)
  ;; media and the delivery API need no session; keeping them outside the session
  ;; middleware also keeps the in-memory store from growing with every image fetch
  (install-middleware *page-app* *media-middleware*)
  (install-middleware *page-app* (with-args *mount* "/api"
                                            (lack:builder *delivery-cors-middleware* *api-app*)))
  ;; the store is the database, not the process, so a restart keeps the owner logged in
  ;; :keep-empty nil: a request that never touches its session leaves nothing behind
  (install-middleware *page-app* (with-args *session*
                                            :store (make-session-store)
                                            :state (session-cookie-state)
                                            :keep-empty nil))
  (install-middleware *page-app* *trim-trailing-slash*)
  (install-middleware *page-app* (with-args *mount* "/admin/api"
                                            (lack:builder *admin-auth-middleware* *admin-api-app*)))
  (install-middleware *page-app* *actions-auth-middleware*)
  (install-middleware *page-app* *actions-middleware*)
  (install-middleware *page-app* *pages-auth-middleware*)
  (static-path *page-app* "/assets/" "assets/")
  (configure *page-app*))

(defvar *app* nil)

(defun app ()
  "The whole app, built on first use. Building it calls ports, so it waits for
something to ask rather than happening when this file loads, before infra may
have."
  (or *app* (setf *app* (build-app))))
