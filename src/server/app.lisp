(defpackage #:koya-server/app
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
  (:import-from #:koya-server/lib/env
                #:dev-mode-p)
  (:import-from #:koya-server/lib/http
                #:make-json-app)
  (:import-from #:koya-server/lib/auth
                #:*admin-auth-middleware*)
  (:import-from #:koya-server/document
                #:~document)
  (:import-from #:koya-server/actions)
  (:export #:*app*
           #:*api-app*
           #:*admin-api-app*
           #:*page-app*
           #:build-app))
(in-package #:koya-server/app)

;;; Delivery API: /api/v1/...  (JSON, API key)
(defparameter *api-app* (make-json-app))
(set-routes *api-app* :system :koya-server :dir "api")

;;; Admin API: /admin/api/... (JSON, owner)
(defparameter *admin-api-app* (make-json-app))
(set-routes *admin-api-app* :system :koya-server :dir "admin-api")

;;; Admin UI pages: / (HTML, owner session)
(defparameter *page-app* (make-app))
(set-routes *page-app* :system :koya-server :dir "pages")

(defmethod process-response :around ((app (eql *page-app*)) result)
  (set-response-header :content-type "text/html; charset=utf-8")
  (call-next-method app (and result (hsx:render-to-string
                                     (hsx:hsx (~document :title (ningle:context :title) result))))))

(defmethod process-response :around ((app (eql *actions-app*)) result)
  (set-response-header :content-type "text/html; charset=utf-8")
  (call-next-method app (and result (hsx:render-to-string (hsx:hsx result)))))

(defun build-app ()
  (clear-middlewares *page-app*)
  (install-middleware *page-app* (with-args *clack-error-middleware* :debug (dev-mode-p)))
  (install-middleware *page-app* *lack-middleware-accesslog*)
  (install-middleware *page-app* *lack-middleware-session*)
  (install-middleware *page-app* *trim-trailing-slash*)
  (install-middleware *page-app* (with-args *lack-middleware-mount* "/api" *api-app*))
  (install-middleware *page-app* (with-args *lack-middleware-mount* "/admin/api"
                                            (lack:builder *admin-auth-middleware* *admin-api-app*)))
  (install-middleware *page-app* *actions-middleware*)
  (static-path *page-app* "/assets/" "assets/")
  (configure *page-app*))

(defparameter *app* (build-app))
