(defpackage #:koya-server/lib/auth
  (:use #:cl)
  (:import-from #:koya-server/lib/env
                #:koya-secret)
  (:import-from #:koya-server/lib/http
                #:fail-api #:header #:json-response #:error-object #:origin-allowed-p)
  (:import-from #:koya-server/db/delivery-keys
                #:space-for-delivery-key)
  (:import-from #:koya-server/db/management-keys
                #:space-for-management-key #:management-key-label)
  (:import-from #:ironclad
                #:constant-time-equal)
  (:import-from #:babel
                #:string-to-octets)
  (:import-from #:lack/request
                #:request-env)
  (:import-from #:bordeaux-threads-2)
  (:import-from #:quri #:uri #:uri-path #:uri-query #:make-uri #:render-uri)
  (:import-from #:koya-server/lib/totp
                #:totp-enabled-p #:totp-code-valid-p)
  (:export #:secure-string=
           #:login-locked-p
           #:note-login-failure
           #:clear-login-failures
           #:calling-space
           #:calling-identity
           #:*admin-auth-middleware*
           #:*actions-auth-middleware*
           #:require-delivery-key
           #:public-path
           #:session-login
           #:session-logout
           #:session-owner-p))
(in-package #:koya-server/lib/auth)

;;; Four keys, three kinds of callers:
;;;  - the owner secret (KOYA_SECRET) logs into the admin UI; the session cookie
;;;    then carries the owner through the UI and the admin API
;;;  - a management key (Bearer, made on a space's keys page) drives the admin API
;;;    without a session: schema deploys, imports, content management from a REPL.
;;;    It belongs to one space and reaches nothing outside it
;;;  - a delivery key (X-KOYA-DELIVERY-KEY, made per space) reads the delivery API
;;;  - the webhook secret is the one koya sends, not one it checks (see lib/webhook)

(defun secure-string= (a b)
  (and (stringp a) (stringp b)
       (= (length a) (length b))
       (constant-time-equal (string-to-octets a :encoding :utf-8) (string-to-octets b :encoding :utf-8))))

(defun bearer-token (env)
  (let ((auth (gethash "authorization" (getf env :headers))))
    (and auth (> (length auth) 7) (string-equal (subseq auth 0 7) "Bearer ")
         (string-trim " " (subseq auth 7)))))

(defun session-owner-p (&optional (session (ningle:context :session)))
  (and session (gethash "owner" session) t))

;;; Failed logins are counted per client address; after +LOGIN-ATTEMPTS+ failures
;;; within +LOGIN-WINDOW-SECONDS+ the address has to wait. Kept in memory: one
;;; process, and a restart clearing it is fine.

(defparameter +login-attempts+ 5)
(defparameter +login-window-seconds+ 300)
(defvar *login-failures* (make-hash-table :test 'equal))
(defvar *login-failures-lock* (bordeaux-threads-2:make-lock :name "koya-login-failures"))

(defun login-locked-p (address)
  "True when ADDRESS has failed too often recently."
  (bordeaux-threads-2:with-lock-held (*login-failures-lock*)
    (let ((entry (gethash address *login-failures*)))
      (and entry
           (>= (car entry) +login-attempts+)
           (< (- (get-universal-time) (cdr entry)) +login-window-seconds+)))))

(defun note-login-failure (address)
  (bordeaux-threads-2:with-lock-held (*login-failures-lock*)
    (let ((entry (gethash address *login-failures*))
          (now (get-universal-time)))
      (setf (gethash address *login-failures*)
            (if (and entry (< (- now (cdr entry)) +login-window-seconds+))
                (cons (1+ (car entry)) now)
                (cons 1 now))))))

(defun clear-login-failures (address)
  (bordeaux-threads-2:with-lock-held (*login-failures-lock*)
    (remhash address *login-failures*)))

(defun session-login (secret &optional code)
  "Mark the current session as the owner when SECRET is right and, with TOTP
enabled, CODE is the current one-time code. Returns T on success, :code when only
the code is wrong or missing, NIL otherwise. The secret is checked first so a
wrong secret never learns whether a code would have been accepted."
  (cond ((not (secure-string= secret (koya-secret))) nil)
        ((and (totp-enabled-p) (not (totp-code-valid-p code))) :code)
        (t (setf (gethash "owner" (ningle:context :session)) t)
           t)))

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

(defun calling-identity ()
  "Who is making this request, to store: \"owner\" or \"key:<label>\". The wording a
page puts around it is the page's, so it can be changed later.

The owner comes first, as *ADMIN-AUTH-MIDDLEWARE* does it: a request carrying
both a session and a key is authorised as the owner. Outside a request -- a
write from the REPL -- it is \"\", the way a deploy from the REPL names nobody."
  (let ((env (and ningle:*request* (request-env ningle:*request*))))
    (cond ((null env) "")
          ((session-env-owner-p env) "owner")
          (t (let ((label (management-key-label (bearer-token env))))
               ;; nothing without one or the other gets past the middleware
               (if label (format nil "key:~a" label) "unknown"))))))

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
              (t (funcall app env))))))
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
            (t (funcall app env)))))
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
