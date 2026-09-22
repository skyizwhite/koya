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
                #:dev-mode-p #:base-url)
  (:import-from #:koya-server/lib/media-store
                #:*media-middleware* #:+max-upload-bytes+)
  (:import-from #:koya-server/lib/http
                #:make-json-app)
  (:import-from #:koya-server/lib/auth
                #:*admin-auth-middleware* #:*actions-auth-middleware*)
  (:import-from #:koya-server/db/sessions
                #:make-session-store #:+session-seconds+)
  (:import-from #:koya-server/document
                #:~document)
  (:export #:*app*
           #:*api-app*
           #:*admin-api-app*
           #:*page-app*
           #:build-app))
(in-package #:koya-server/app)

;;; Delivery API: /api/v1/...  (JSON, delivery key)
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

(defun prefix-p (prefix path)
  (and (>= (length path) (length prefix)) (string= prefix path :end2 (length prefix))))

(defparameter *cache-control-middleware*
  (lambda (app)
    (lambda (env)
      ;; taken before the call: the static middleware strips its prefix from path-info
      (let* ((path (getf env :path-info))
             (response (funcall app env)))
        (when (and (listp response) (not (getf (second response) :cache-control)))
          (setf (getf (second response) :cache-control)
                (if (and (prefix-p "/assets/" path) (eql (first response) 200))
                    ;; asset URLs carry ?v=<version> (see lib/assets), so the file behind one never changes
                    "public, max-age=31536000, immutable"
                    ;; pages and both APIs are per-request and often per-owner
                    "no-store")))
        response)))
  "Cache-Control for everything that did not set one: immutable assets, no-store otherwise.
/media/ sets its own (see *media-middleware*).")

(defparameter +max-body-bytes+ (+ +max-upload-bytes+ (* 1024 1024))
  "Largest request body accepted: the media upload limit plus room for the other parts.")

(defparameter *body-limit-middleware*
  (lambda (app)
    (lambda (env)
      (let ((length (getf env :content-length)))
        (if (and (integerp length) (> length +max-body-bytes+))
            ;; before anything parses the body: lack reads a multipart body whole
            (let ((message (format nil "Request body is limited to ~a MB" (floor +max-body-bytes+ (* 1024 1024)))))
              ;; htmx swaps an error response in, so it gets a fragment rather than JSON
              (if (gethash "hx-request" (getf env :headers))
                  (list 413 (list :content-type "text/html; charset=utf-8" :cache-control "no-store")
                        (list (format nil "<p class=\"text-sm text-danger\">~a</p>" message)))
                  (list 413 (list :content-type "application/json; charset=utf-8" :cache-control "no-store")
                        (list (format nil "{\"error\":{\"code\":\"too_large\",\"message\":\"~a\"}}" message)))))
            (funcall app env)))))
  "Rejects oversized bodies by Content-Length, outermost, so no parser allocates for them.")

(defun session-cookie-state ()
  "The owner session cookie: HttpOnly so scripts cannot read it, SameSite=Lax so
other sites cannot post with it, Secure when the site is served over HTTPS."
  ;; the state package has no ASDF system of its own, so it is named in full;
  ;; lack-middleware-session (imported above) loads it
  (lack/middleware/session/state/cookie:make-cookie-state
                     :httponly t
                     :samesite :lax
                     :expires +session-seconds+
                     :secure (and (>= (length (base-url)) 8) (string-equal "https://" (base-url) :end2 8))))

(defun build-app ()
  (clear-middlewares *page-app*)
  (install-middleware *page-app* (with-args *clack-error-middleware* :debug (dev-mode-p)))
  (install-middleware *page-app* *body-limit-middleware*)
  (install-middleware *page-app* *cache-control-middleware*)
  (install-middleware *page-app* *lack-middleware-accesslog*)
  ;; media and the delivery API need no session; keeping them outside the session
  ;; middleware also keeps the in-memory store from growing with every image fetch
  (install-middleware *page-app* *media-middleware*)
  (install-middleware *page-app* (with-args *lack-middleware-mount* "/api" *api-app*))
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
