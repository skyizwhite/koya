(defpackage #:koya-server/web/auth
  (:use #:cl)
  (:import-from #:koya-server/web/http
                #:fail-api #:header #:json-response #:error-object #:origin-allowed-p)
  (:import-from #:koya-server/usecases/keys
                #:space-for-delivery-key #:space-for-management-key #:management-key-label)
  (:import-from #:koya-server/usecases/auth
                #:check-login)
  (:import-from #:koya-server/usecases/actor
                #:*actor*)
  (:import-from #:lack/request
                #:request-env)
  (:import-from #:quri #:uri #:uri-path #:uri-query #:make-uri #:render-uri)
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

(defun session-login (secret &optional code)
  "Mark the current session as the owner when CHECK-LOGIN lets SECRET and CODE
in. Returns what CHECK-LOGIN does."
  (let ((result (check-login secret code)))
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

(defun calling-identity (env)
  "Who ENV comes from, as *ACTOR* holds it: \"owner\" or \"key:<label>\". The
wording a page puts around it is the page's, so it can be changed later.

The owner comes first, as *ADMIN-AUTH-MIDDLEWARE* does it: a request carrying
both a session and a key is authorised as the owner."
  (if (session-env-owner-p env)
      "owner"
      (let ((label (management-key-label (bearer-token env))))
        ;; nothing without one or the other gets past the middleware
        (if label (format nil "key:~a" label) "unknown"))))

(defun cross-origin-write-p (env)
  "A state-changing request whose Origin/Referer does not match this server. The
session cookie would otherwise let a page on another site drive the admin API."
  (let ((headers (getf env :headers)))
    (and (member (getf env :request-method) '(:post :put :patch :delete))
         (not (origin-allowed-p (gethash "origin" headers) (gethash "referer" headers) (gethash "host" headers))))))

(defparameter *admin-auth-middleware*
  (lambda (app)
    (lambda (env)
      (let* ((owner (session-env-owner-p env))
             (space (and (not owner) (space-for-management-key (bearer-token env)))))
        (cond ((and (not owner) (null space))
               (json-response 401 (error-object "unauthorized" "Log in, or send a management key as a Bearer token")))
              ;; deny by default: a key reaches its own space and nothing else,
              ;; whatever route is added later
              ((and space (not (space-path-p space (getf env :path-info))))
               (json-response 403 (error-object "forbidden"
                                                (format nil "This management key only reaches space ~a" space))))
              ((cross-origin-write-p env)
               (json-response 403 (error-object "forbidden" "Cross-origin request rejected")))
              (t (let ((*actor* (calling-identity env)))
                   (funcall app env)))))))
  "Lack middleware guarding the admin API: the owner's session reaches every space,
a Bearer management key only its own, and no request writes cross-origin.")

(defun actions-path-p (path)
  ;; the prefix ningle-actions mounts under, matched as lack's mount matches it
  (and (stringp path)
       (or (string= path "/actions")
           (and (> (length path) 9) (string= "/actions/" path :end2 9)))))

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

(defparameter *actions-auth-middleware*
  (lambda (app)
    (lambda (env)
      (cond ((not (actions-path-p (getf env :path-info))) (funcall app env))
            ;; an action answers a fragment of a page, never a page: a link or a
            ;; plain form post has no business here
            ((not (htmx-request-p env))
             (list 400 (list :content-type "text/plain; charset=utf-8") (list "Bad Request")))
            ((not (or (session-env-owner-p env) (public-path-p (getf env :path-info))))
             ;; htmx follows HX-Redirect, so the owner logs in and comes back
             (list 401 (list :content-type "text/html; charset=utf-8" :hx-redirect (login-location env))
                   (list "<p class=\"text-sm text-danger\">Log in again to continue.</p>")))
            ((cross-origin-write-p env) (html-forbidden "Cross-origin request rejected."))
            (t (let ((*actor* (if (session-env-owner-p env) "owner" "")))
                 (funcall app env))))))
  "Lack middleware guarding every ningle-actions endpoint: htmx requests only, owner
session only (but for a PUBLIC-PATH), no cross-origin writes. Installed just
outside *ACTIONS-MIDDLEWARE*, so an action defined later is covered without
checking for itself.")

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

(defun asset-path-p (path)
  ;; the login page is drawn with them
  (and (stringp path) (> (length path) 8) (string= "/assets/" path :end2 8)))

(defparameter *pages-auth-middleware*
  (lambda (app)
    (lambda (env)
      (let ((path (getf env :path-info)))
        (if (or (session-env-owner-p env)
                (public-path-p path)
                (asset-path-p path)
                ;; *ACTIONS-AUTH-MIDDLEWARE* has its own answer for these
                (actions-path-p path))
            (funcall app env)
            (list 302 (list :location (page-login-location env)) '())))))
  "Lack middleware guarding every page: the owner's session only, but for a
PUBLIC-PATH. Installed inside everything mounted before the pages, so a page
defined later is covered without checking for itself, and a path that is no
page goes to the login page as well rather than saying it does not exist.")
