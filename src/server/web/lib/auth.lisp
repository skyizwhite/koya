(defpackage #:koya-server/web/lib/auth
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http
                #:json-response #:error-object #:origin-allowed-p)
  (:import-from #:koya-server/usecases/keys
                #:space-for-delivery-key #:space-for-management-key #:management-key-label)
  (:import-from #:koya-server/usecases/auth
                #:check-login)
  (:import-from #:koya-server/usecases/actor
                #:*actor* #:+owner+ #:key-actor)
  (:import-from #:jingle
                #:*request* #:context #:request-env)
  (:import-from #:lack-mw
                #:mw-every #:mw-except)
  (:import-from #:quri #:uri #:uri-path #:uri-query #:make-uri #:render-uri #:url-decode)
  (:import-from #:hsx #:hsx #:render-to-string)
  (:import-from #:koya-server/web/lib/toast #:~toast)
  (:export #:calling-space
           #:*mw-admin-auth*
           #:*mw-actions-auth*
           #:*mw-pages-auth*
           #:*mw-delivery-auth*
           #:public-path
           #:local-path-p
           #:session-login
           #:session-id
           #:session-logout
           #:session-owner-p))
(in-package #:koya-server/web/lib/auth)

(defun bearer-token (env)
  (let ((auth (gethash "authorization" (getf env :headers))))
    (and auth (> (length auth) 7) (string-equal (subseq auth 0 7) "Bearer ")
         (string-trim " " (subseq auth 7)))))

(defun session-owner-p (&optional (session (context :session)))
  (and session (gethash "owner" session) t))

(defun renew-session-id ()
  (setf (getf (getf (request-env *request*) :lack.session.options) :change-id) t))

(defun session-id ()
  (getf (getf (request-env *request*) :lack.session.options) :id))

(defun session-login (secret &optional code)
  (let ((result (check-login secret code)))
    (when (eq result t)
      (renew-session-id)
      (setf (gethash "owner" (context :session)) t))
    result))

(defun session-logout ()
  (renew-session-id)
  (remhash "owner" (context :session)))

(defun session-env-owner-p (env)
  (let ((session (getf env :lack.session)))
    (and session (gethash "owner" session) t)))

(defun path-segments (path)
  (remove "" (uiop:split-string (or path "") :separator "/") :test #'string=))

(defun space-path-p (space path)
  (let ((segments (path-segments path)))
    (cond ((equal segments '("me")) t)
          ((null segments) nil)
          (t (string= (first segments) space)))))

(defun calling-space ()
  (space-for-management-key (bearer-token (request-env *request*))))

(defun cross-origin-write-p (env)
  (let ((headers (getf env :headers)))
    (and (member (getf env :request-method) '(:post :put :patch :delete))
         (not (origin-allowed-p (gethash "origin" headers) (gethash "referer" headers) (gethash "host" headers))))))

(defun same-origin-writes (reject)
  (lambda (app)
    (lambda (env)
      (if (cross-origin-write-p env)
          (funcall reject)
          (funcall app env)))))

(defparameter *management-key*
  (lambda (app)
    (lambda (env)
      (let* ((key (bearer-token env))
             (space (space-for-management-key key)))
        (cond ((null space)
               (json-response 401 (error-object "unauthorized" "Send a management key as a Bearer token")))
              ((not (space-path-p space (getf env :path-info)))
               (json-response 403 (error-object "forbidden"
                                                (format nil "This management key only reaches space ~a" space))))
              (t (let ((*actor* (let ((label (management-key-label key)))
                                  (if label (key-actor label) "unknown"))))
                   (funcall app env))))))))

(defparameter *mw-admin-auth* *management-key*)

(defun html-forbidden (message)
  (list 403 (list :content-type "text/html; charset=utf-8")
        (list (format nil "<p class=\"text-sm text-danger\">~a</p>" message))))

(defvar *public-paths* (make-hash-table :test 'equal))

(defun public-path (url)
  (setf (gethash (subseq url 0 (position #\? url)) *public-paths*) t)
  url)

(defun public-path-p (path)
  (and (gethash path *public-paths*) t))

(defun page-request-p (env)
  (equal (gethash "nm-request" (getf env :headers)) "true"))

(defun login-location (env)
  (let* ((current (ignore-errors (uri (gethash "referer" (getf env :headers)))))
         (next (and current (render-uri (make-uri :path (or (uri-path current) "/") :query (uri-query current))))))
    (if (and next (string/= next "/"))
        (render-uri (make-uri :path "/login" :query `(("next" . ,next))))
        "/login")))

(defun public-request-p (env)
  (let ((path (ignore-errors (url-decode (or (uri-path (uri (getf env :request-uri))) "")))))
    (and path (public-path-p path))))

(defparameter *page-requests-only*
  (lambda (app)
    (lambda (env)
      (if (page-request-p env)
          (funcall app env)
          (list 400 (list :content-type "text/plain; charset=utf-8") (list "Bad Request"))))))

(defun session-ended (login)
  (render-to-string
   (hsx (~toast :kind :error :clickable t :binds "{ oninit: () => koya.closeDialogs() }"
                :message (hsx (<> "The session has ended. "
                                  (a :href login :target "_blank" :rel "noopener" :class "font-semibold underline"
                                     "Log in in a new tab")
                                  ", then try again here."))))))

(defparameter *action-session*
  (lambda (app)
    (lambda (env)
      (if (session-env-owner-p env)
          (funcall app env)
          (list 401 (list :content-type "text/html; charset=utf-8")
                (list (session-ended (login-location env))))))))

(defparameter *action-actor*
  (lambda (app)
    (lambda (env)
      (if (session-env-owner-p env)
          (let ((*actor* +owner+))
            (funcall app env))
          (funcall app env)))))

(defparameter *mw-actions-auth*
  (mw-every *page-requests-only*
            (mw-except #'public-request-p *action-session*)
            (same-origin-writes (lambda () (html-forbidden "Cross-origin request rejected.")))
            *action-actor*))

(defparameter *mw-delivery-auth*
  (lambda (app)
    (lambda (env)
      (let* ((key (let ((header (gethash "x-koya-delivery-key" (getf env :headers))))
                    (and header (string-trim " " header))))
             (key-space (space-for-delivery-key key)))
        (cond ((null key)
               (json-response 401 (error-object "unauthorized" "X-KOYA-DELIVERY-KEY header is required")))
              ((null key-space)
               (json-response 401 (error-object "unauthorized" "Invalid delivery key")))
              ((not (equal key-space (second (path-segments (getf env :path-info)))))
               (json-response 403 (error-object "forbidden" "Delivery key does not belong to this space")))
              (t (funcall app env)))))))

(defun local-path-p (path)
  (and (stringp path)
       (plusp (length path))
       (char= (char path 0) #\/)
       (not (and (> (length path) 1) (char= (char path 1) #\/)))
       (notany (lambda (c) (or (char< c #\Space) (char= c #\\))) path)))

(defun path-and-query (url)
  (let ((uri (uri url)))
    (render-uri (make-uri :path (or (uri-path uri) "/") :query (uri-query uri)))))

(defun page-login-location (env)
  (let ((next (ignore-errors (path-and-query (getf env :request-uri)))))
    (if (and (local-path-p next) (string/= next "/"))
        (render-uri (make-uri :path "/login" :query `(("next" . ,next))))
        "/login")))

(defparameter *page-session*
  (lambda (app)
    (lambda (env)
      (if (session-env-owner-p env)
          (funcall app env)
          (list 302 (list :location (page-login-location env)) '())))))

(defparameter *mw-pages-auth*
  (mw-except #'public-request-p *page-session*))
