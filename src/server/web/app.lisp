(defpackage #:koya-server/web/app
  (:use #:cl)
  (:import-from #:jingle
                #:make-app #:set-response-header #:process-response)
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
  (:import-from #:koya-server/web/lib/media #:media-app)
  (:import-from #:koya-server/web/lib/http
                #:make-json-app)
  (:import-from #:koya-server/web/lib/middlewares
                #:*mw-temporary-file* #:*mw-max-body*
                #:*mw-default-cache-control* #:*mw-delivery-cors* #:+max-body-bytes+)
  (:import-from #:smart-buffer)
  (:import-from #:koya-server/usecases/auth #:make-session-store #:+session-seconds+)
  (:import-from #:koya-server/web/lib/auth
                #:*mw-delivery-auth* #:*mw-admin-auth* #:*mw-actions-auth* #:*mw-pages-auth*)
  (:import-from #:koya-server/web/lib/presenters)
  (:import-from #:koya-server/web/lib/document
                #:~document #:page-title)
  (:export #:app
           #:*app*
           #:*api-app*
           #:*admin-api-app*
           #:*page-app*
           #:install-routes
           #:build-app))
(in-package #:koya-server/web/app)

(defparameter *api-app* (make-json-app))

(defparameter *admin-api-app* (make-json-app))

(defparameter *page-app* (make-app))

(defun install-routes ()
  (set-routes *api-app* :system :koya-server :dir "web/api")
  (set-routes *admin-api-app* :system :koya-server :dir "web/admin-api")
  (set-routes *page-app* :system :koya-server :dir "web/pages"))

(install-routes)

(defmethod process-response :around ((app (eql *page-app*)) result)
  (if (and (consp result) (integerp (first result)))
      (call-next-method)
      (progn
        (set-response-header :content-type "text/html; charset=utf-8")
        (call-next-method app (and result (hsx:render-to-string
                                           (hsx:hsx (~document :title (page-title) result))))))))

(defmethod process-response :around ((app (eql *actions-app*)) result)
  (set-response-header :content-type "text/html; charset=utf-8")
  (call-next-method app (and result (hsx:render-to-string (hsx:hsx result)))))

(defun session-cookie-state ()
  (make-cookie-state :httponly t
                     :samesite :lax
                     :expires +session-seconds+
                     :secure (and (>= (length (public-url)) 8) (string-equal "https://" (public-url) :end2 8))))

(defun build-app ()
  (setf smart-buffer:*default-disk-limit* +max-body-bytes+)
  (let ((session (with-args *mw-session*
                   :store (make-session-store)
                   :state (session-cookie-state)
                   :keep-empty nil)))
    (lack:builder
     *mw-temporary-file*
     *mw-accesslog*
     *mw-default-cache-control*
     (with-args *mw-recovery* :dev-mode (dev-mode-p))
     *mw-max-body*
     (with-args *mw-mount* "/api"
       (lack:builder *mw-delivery-cors* *mw-trim-trailing-slash* *mw-delivery-auth* *api-app*))
     (with-args *mw-mount* "/assets" (make-instance 'lack-app-file :root #p"assets/"))
     (with-args *mw-mount* "/media" #'media-app)
     (with-args *mw-mount* "/admin/api"
       (lack:builder *mw-trim-trailing-slash* session *mw-admin-auth* *admin-api-app*))
     (with-args *mw-mount* "/actions"
       (lack:builder session *mw-actions-auth* *actions-app*))
     (lack:builder *mw-trim-trailing-slash* session *mw-pages-auth* *page-app*))))

(defvar *app* nil)

(defun app ()
  (or *app* (setf *app* (build-app))))
