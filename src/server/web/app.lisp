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
  (:import-from #:lack/middleware/mount
                #:*lack-middleware-mount*)
  (:import-from #:lack/middleware/session
                #:*lack-middleware-session*)
  (:import-from #:lack/middleware/accesslog
                #:*lack-middleware-accesslog*)
  (:import-from #:lack-mw
                #:with-args #:*trim-trailing-slash*)
  (:import-from #:clack-errors
                #:*clack-error-middleware*)
  (:import-from #:koya-server/usecases/system #:dev-mode-p #:public-url)
  (:import-from #:koya-server/web/media #:*media-middleware*)
  (:import-from #:koya-server/web/http
                #:make-json-app)
  (:import-from #:koya-server/web/middlewares
                #:*body-limit-middleware* #:*cache-control-middleware* #:*delivery-cors-middleware*)
  (:import-from #:koya-server/usecases/auth #:make-session-store #:+session-seconds+)
  (:import-from #:koya-server/web/auth
                #:*admin-auth-middleware* #:*actions-auth-middleware*)
  (:import-from #:koya-server/web/document
                #:~document #:page-title)
  (:export #:*app*
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
  ;; the state package has no ASDF system of its own, so it is named in full;
  ;; lack-middleware-session (imported above) loads it
  (lack/middleware/session/state/cookie:make-cookie-state
                     :httponly t
                     :samesite :lax
                     :expires +session-seconds+
                     :secure (and (>= (length (public-url)) 8) (string-equal "https://" (public-url) :end2 8))))

(defun build-app ()
  (clear-middlewares *page-app*)
  (install-middleware *page-app* (with-args *clack-error-middleware* :debug (dev-mode-p)))
  (install-middleware *page-app* *body-limit-middleware*)
  (install-middleware *page-app* *cache-control-middleware*)
  (install-middleware *page-app* *lack-middleware-accesslog*)
  ;; media and the delivery API need no session; keeping them outside the session
  ;; middleware also keeps the in-memory store from growing with every image fetch
  (install-middleware *page-app* *media-middleware*)
  (install-middleware *page-app* (with-args *lack-middleware-mount* "/api"
                                            (lack:builder *delivery-cors-middleware* *api-app*)))
  ;; the store is the database, not the process, so a restart keeps the owner logged in
  ;; :keep-empty nil: a request that never touches its session leaves nothing behind
  (install-middleware *page-app* (with-args *lack-middleware-session*
                                            :store (make-session-store)
                                            :state (session-cookie-state)
                                            :keep-empty nil))
  (install-middleware *page-app* *trim-trailing-slash*)
  (install-middleware *page-app* (with-args *lack-middleware-mount* "/admin/api"
                                            (lack:builder *admin-auth-middleware* *admin-api-app*)))
  (install-middleware *page-app* *actions-auth-middleware*)
  (install-middleware *page-app* *actions-middleware*)
  (static-path *page-app* "/assets/" "assets/")
  (configure *page-app*))

(defparameter *app* (build-app))
