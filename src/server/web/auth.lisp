(defpackage #:koya-server/web/auth
  (:use #:cl)
  (:import-from #:koya-server/web/http
                #:fail-api #:header #:json-response #:error-object #:origin-allowed-p)
  (:import-from #:koya-server/usecases/keys
                #:space-for-delivery-key #:space-for-management-key #:management-key-label)
  (:import-from #:koya-server/usecases/auth
                #:attempt-login)
  (:import-from #:koya-server/usecases/actor
                #:*actor* #:+owner+ #:key-actor)
  (:import-from #:lack/request
                #:request-env)
  (:import-from #:lack-mw
                #:mw-every #:mw-some #:mw-except)
  (:import-from #:quri #:uri #:uri-path #:uri-query #:make-uri #:render-uri #:url-decode)
  (:export #:calling-space
           #:*admin-auth-middleware*
           #:*actions-auth-middleware*
           #:*pages-auth-middleware*
           #:require-delivery-key
           #:public-path
           #:local-path-p
           #:session-login
           #:session-logout
           #:session-owner-p))
(in-package #:koya-server/web/auth)

;;; Who a request comes from, and what it may reach (usecases/keys has the
;;; kinds of key):
;;;  - the owner logs into the admin UI; the session cookie then carries the owner
;;;    through the UI and the admin API
;;;  - a management key (Bearer, made on a space's keys page) drives the admin API
;;;    without a session: schema deploys, imports, content management from a REPL
;;;  - a delivery key (X-KOYA-DELIVERY-KEY, made per space) reads the delivery API
;;;
;;; The guards bind *ACTOR* to whoever is let through, so what a request changes
;;; names them.

(defun bearer-token (env)
  (let ((auth (gethash "authorization" (getf env :headers))))
    (and auth (> (length auth) 7) (string-equal (subseq auth 0 7) "Bearer ")
         (string-trim " " (subseq auth 7)))))

(defun session-owner-p (&optional (session (ningle:context :session)))
  (and session (gethash "owner" session) t))

(defun session-login (address secret &optional code)
  "Mark the current session as the owner when ATTEMPT-LOGIN lets ADDRESS in
with SECRET and CODE. Returns what ATTEMPT-LOGIN does."
  (let ((result (attempt-login address secret code)))
    (when (eq result t)
      (setf (gethash "owner" (ningle:context :session)) t))
    result))

(defun session-logout ()
  (remhash "owner" (ningle:context :session)))

(defun session-env-owner-p (env)
  "True for the owner's session. The owner secret itself is not accepted on the
admin API: it is the login password, kept behind the second factor."
  (let ((session (getf env :lack.session)))
    (and session (gethash "owner" session) t)))

(defun path-segments (path)
  (remove "" (uiop:split-string (or path "") :separator "/") :test #'string=))

(defun space-path-p (space path)
  "True when PATH, taken under /admin/api, stays inside SPACE. Every route but
/me is <resource>/<space>/..., so the space is the second segment; a path without
one is refused rather than guessed at."
  (let ((segments (path-segments path)))
    (cond ((equal segments '("me")) t)
          ((< (length segments) 2) nil)
          (t (string= (second segments) space)))))

(defun calling-space ()
  "The space of the management key making this request, or NIL for the owner's
session, which reaches every space."
  (space-for-management-key (bearer-token (request-env ningle:*request*))))

(defun cross-origin-write-p (env)
  "A state-changing request whose Origin/Referer does not match this server. The
session cookie would otherwise let a page on another site drive the admin API."
  (let ((headers (getf env :headers)))
    (and (member (getf env :request-method) '(:post :put :patch :delete))
         (not (origin-allowed-p (gethash "origin" headers) (gethash "referer" headers) (gethash "host" headers))))))

(defun same-origin-writes (reject)
  "Middleware answering a CROSS-ORIGIN-WRITE-P request with (funcall REJECT)."
  (lambda (app)
    (lambda (env)
      (if (cross-origin-write-p env)
          (funcall reject)
          (funcall app env)))))

(defparameter *owner-session*
  (lambda (app)
    (lambda (env)
      (if (session-env-owner-p env)
          (let ((*actor* +owner+))
            (funcall app env))
          ;; never sent: *ADMIN-AUTH-MIDDLEWARE* tries *MANAGEMENT-KEY* next, and
          ;; answers with what that says
          (json-response 401 (error-object "unauthorized" "Log in")))))
  "The admin API for the owner's session, which reaches every space.")

(defparameter *management-key*
  (lambda (app)
    (lambda (env)
      (let* ((key (bearer-token env))
             (space (space-for-management-key key)))
        (cond ((null space)
               (json-response 401 (error-object "unauthorized" "Log in, or send a management key as a Bearer token")))
              ;; deny by default: a key reaches its own space and nothing else,
              ;; whatever route is added later
              ((not (space-path-p space (getf env :path-info)))
               (json-response 403 (error-object "forbidden"
                                                (format nil "This management key only reaches space ~a" space))))
              ;; the key may have been revoked since SPACE-FOR-MANAGEMENT-KEY read it
              (t (let ((*actor* (let ((label (management-key-label key)))
                                  (if label (key-actor label) "unknown"))))
                   (funcall app env)))))))
  "The admin API for a Bearer management key, which reaches its own space.")

(defparameter *admin-auth-middleware*
  ;; the owner comes first: a request carrying both a session and a key is the owner's.
  ;; When neither lets it in, *MANAGEMENT-KEY*'s answer, the last, is the one sent
  (mw-every (mw-some *owner-session* *management-key*)
            (same-origin-writes
             (lambda () (json-response 403 (error-object "forbidden" "Cross-origin request rejected")))))
  "Lack middleware guarding the admin API: the owner's session reaches every space,
a Bearer management key only its own, and no request writes cross-origin.")

(defun html-forbidden (message)
  (list 403 (list :content-type "text/html; charset=utf-8")
        (list (format nil "<p class=\"text-sm text-danger\">~a</p>" message))))

;;; Paths reachable without the owner's session. Everything else behind a guard
;;; needs one; a path is let through by being named here, where it is defined,
;;; so what is open can be found by looking for PUBLIC-PATH.

(defvar *public-paths* (make-hash-table :test 'equal))

(defun public-path (url)
  "Let URL's path (its query dropped) through without a session. Returns URL."
  (setf (gethash (subseq url 0 (position #\? url)) *public-paths*) t)
  url)

(defun public-path-p (path)
  (and (gethash path *public-paths*) t))

(defun htmx-request-p (env)
  (equal (gethash "hx-request" (getf env :headers)) "true"))

(defun login-location (env)
  "Where a request that has lost its session goes: the login page, coming back to
the page htmx says it was sent from. The login page checks NEXT is a local path."
  (let* ((current (ignore-errors (uri (gethash "hx-current-url" (getf env :headers)))))
         (next (and current (render-uri (make-uri :path (or (uri-path current) "/") :query (uri-query current))))))
    (if (and next (string/= next "/"))
        (render-uri (make-uri :path "/login" :query `(("next" . ,next))))
        "/login")))

(defun public-request-p (env)
  ;; the path as asked for, decoded as path-info is: under a mount, path-info has
  ;; lost the mount's prefix. The request line may be in absolute form (http://host/...)
  (let ((path (ignore-errors (url-decode (or (uri-path (uri (getf env :request-uri))) "")))))
    (and path (public-path-p path))))

(defparameter *htmx-only*
  (lambda (app)
    (lambda (env)
      ;; an action answers a fragment of a page, never a page: a link or a
      ;; plain form post has no business here
      (if (htmx-request-p env)
          (funcall app env)
          (list 400 (list :content-type "text/plain; charset=utf-8") (list "Bad Request"))))))

(defparameter *action-session*
  (lambda (app)
    (lambda (env)
      (if (session-env-owner-p env)
          (funcall app env)
          ;; htmx follows HX-Redirect, so the owner logs in and comes back
          (list 401 (list :content-type "text/html; charset=utf-8" :hx-redirect (login-location env))
                (list "<p class=\"text-sm text-danger\">Log in again to continue.</p>"))))))

(defparameter *action-actor*
  (lambda (app)
    (lambda (env)
      (if (session-env-owner-p env)
          (let ((*actor* +owner+))
            (funcall app env))
          (funcall app env)))))

(defparameter *actions-auth-middleware*
  (mw-every *htmx-only*
            ;; a PUBLIC-PATH skips the session only, not the other checks
            (mw-except #'public-request-p *action-session*)
            (same-origin-writes (lambda () (html-forbidden "Cross-origin request rejected.")))
            *action-actor*)
  "Lack middleware guarding every ningle-actions endpoint: htmx requests only, owner
session only (but for a PUBLIC-PATH), no cross-origin writes. Stacked on the
actions app, so an action defined later is covered without checking for itself.")

(defun require-delivery-key (space)
  "Signal 401/403 unless the request carries a delivery key valid for SPACE."
  (let* ((key (header "x-koya-delivery-key"))
         (key-space (space-for-delivery-key key)))
    (cond ((null key) (fail-api 401 "unauthorized" "X-KOYA-DELIVERY-KEY header is required"))
          ((null key-space) (fail-api 401 "unauthorized" "Invalid delivery key"))
          ((string/= key-space space) (fail-api 403 "forbidden" "Delivery key does not belong to this space"))
          (t t))))

(defun local-path-p (path)
  "True for a path on this server. What the login page redirects to comes from the
URL, so anything that a browser could read as another host (//evil, /\\evil) is out."
  (and (stringp path)
       (plusp (length path))
       (char= (char path 0) #\/)
       (not (and (> (length path) 1) (char= (char path 1) #\/)))
       (notany (lambda (c) (or (char< c #\Space) (char= c #\\))) path)))

(defun path-and-query (url)
  (let ((uri (uri url)))
    (render-uri (make-uri :path (or (uri-path uri) "/") :query (uri-query uri)))))

;;; Pages are guarded like the rest: a request for any page without the owner's
;;; session goes to the login page, and comes back to that page afterwards. A
;;; page answers only its owner without saying so, and what is open is what
;;; names itself with PUBLIC-PATH.

(defun page-login-location (env)
  "The login page, coming back to the page ENV asks for."
  ;; the raw request line: path-info is decoded, and an encoded ? or / would change meaning
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

(defparameter *pages-auth-middleware*
  (mw-except #'public-request-p *page-session*)
  "Lack middleware guarding every page: the owner's session only, but for a
PUBLIC-PATH. Stacked on the pages app, which answers whatever no other app is
mounted at, so a page defined later is covered without checking for itself, and
a path that is no page goes to the login page as well rather than saying it
does not exist.")
