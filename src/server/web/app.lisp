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
                #:with-args #:*mw-trim-trailing-slash* #:*mw-recovery*
                #:*mw-mount* #:*mw-session* #:*mw-accesslog* #:make-cookie-state)
  (:import-from #:koya-server/usecases/system #:dev-mode-p #:public-url)
  (:import-from #:koya-server/web/media #:media-app)
  (:import-from #:koya-server/web/http
                #:make-json-app)
  (:import-from #:koya-server/web/middlewares
                #:*mw-temporary-file* #:*mw-max-body*
                #:*mw-default-cache-control* #:*mw-delivery-cors* #:+max-body-bytes+)
  (:import-from #:smart-buffer)
  (:import-from #:koya-server/usecases/auth #:make-session-store #:+session-seconds+)
  (:import-from #:koya-server/web/auth
                #:*mw-admin-auth* #:*mw-actions-auth* #:*mw-pages-auth*)
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
  (let ((session (with-args *mw-session*
                   :store (make-session-store)
                   :state (session-cookie-state)
                   :keep-empty nil)))
    (lack:builder
     *mw-temporary-file*
     ;; outside *MW-RECOVERY*, so a 500 is logged and not cached like any answer
     *mw-accesslog*
     *mw-default-cache-control*
     ;; the JSON apps answer the errors of their routes themselves (web/http); an error
     ;; in a middleware stacked on them, such as a guard's, is answered here in HTML
     (with-args *mw-recovery* :dev-mode (dev-mode-p))
     *mw-max-body*
     ;; CORS outside the trimming, so its redirect carries CORS headers as well
     (with-args *mw-mount* "/api"
       (lack:builder *mw-delivery-cors* *mw-trim-trailing-slash* *api-app*))
     ;; files need no session: none is read for them
     (with-args *mw-mount* "/assets" (make-instance 'lack-app-file :root #p"assets/"))
     (with-args *mw-mount* "/media" #'media-app)
     (with-args *mw-mount* "/admin/api"
       (lack:builder *mw-trim-trailing-slash* session *mw-admin-auth* *admin-api-app*))
     (with-args *mw-mount* "/actions"
       (lack:builder session *mw-actions-auth* *actions-app*))
     (lack:builder *mw-trim-trailing-slash* session *mw-pages-auth* *page-app*))))

(defvar *app* nil)

(defun app ()
  "The whole app, built on first use. Building it calls ports, so it waits for
something to ask rather than happening when this file loads, before infra may
have."
  (or *app* (setf *app* (build-app))))
