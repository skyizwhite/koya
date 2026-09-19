(defpackage #:koya-server/lib/page
  (:use #:cl #:hsx)
  (:import-from #:jingle
                #:redirect #:set-response-status #:get-request-header)
  (:import-from #:ningle
                #:context)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:import-from #:koya-server/lib/auth
                #:session-owner-p)
  (:import-from #:koya-server/lib/env
                #:base-url)
  (:import-from #:quri
                #:uri #:uri-host #:uri-port)
  (:export #:with-owner
           #:with-owner-post
           #:owner-p
           #:set-title
           #:page-title
           #:redirect-to
           #:same-origin-p
           #:param
           #:set-flash
           #:take-flash
           #:expand-url-template
           #:short-time
           #:~layout
           #:~status-badge
           #:~flash
           #:~errors
           #:~empty-state
           #:space-url
           #:model-url
           #:content-url))
(in-package #:koya-server/lib/page)

;;; Helpers shared by the admin UI pages.

(defun owner-p () (session-owner-p))

(defun set-title (title) (setf (context :title) title))
(defun page-title () (context :title))

(defun redirect-to (path &optional (status 303))
  (redirect path status))

;;; One-shot messages carried in the session across a redirect.

(defun set-flash (message &optional (kind :ok))
  (let ((session (context :session)))
    (when session (setf (gethash "flash" session) (list message kind)))))

(defun take-flash ()
  "Return (values message kind) once, then forget it."
  (let* ((session (context :session))
         (flash (and session (gethash "flash" session))))
    (when flash
      (remhash "flash" session)
      (values (first flash) (second flash)))))

(defun short-time (iso)
  "2026-09-20T05:04:03.123Z -> 2026-09-20 05:04 UTC"
  (if (and (stringp iso) (>= (length iso) 16))
      (format nil "~a ~a UTC" (subseq iso 0 10) (subseq iso 11 16))
      (or iso "")))

(defun expand-url-template (template &key id draft-key)
  "Fill {CONTENT_ID} and {DRAFT_KEY} in a model's preview/public URL template."
  (and template
       (regex-replace-all "\\{DRAFT_KEY\\}"
                          (regex-replace-all "\\{CONTENT_ID\\}" template (or id ""))
                          (or draft-key ""))))

(defun header-host (name)
  (let ((v (first (get-request-header name))))
    (and v (let ((u (ignore-errors (uri (string-trim " " v)))))
             (and u (uri-host u) (format nil "~a~@[:~a~]" (uri-host u) (uri-port u)))))))

(defun same-origin-p ()
  "True when the request's Origin (or Referer) matches the Host header or KOYA_BASE_URL.
Requests without either header are accepted (non-browser clients)."
  (let ((origin (or (header-host "origin") (header-host "referer"))))
    (or (null origin)
        (let ((host (string-trim " " (or (first (get-request-header "host")) "")))
              (base (ignore-errors (let ((u (uri (base-url)))) (format nil "~a~@[:~a~]" (uri-host u) (uri-port u))))))
          (or (string-equal origin host) (and base (string-equal origin base)))))))

(defmacro with-owner (&body body)
  "Run BODY for the logged-in owner, otherwise redirect to the login page."
  `(if (owner-p)
       (progn ,@body)
       (redirect-to "/login" 302)))

(defmacro with-owner-post (&body body)
  "Like WITH-OWNER for form posts: also rejects cross-origin submissions."
  `(cond ((not (owner-p)) (redirect-to "/login" 302))
         ((not (same-origin-p)) (set-response-status 403) (hsx (p "Forbidden: cross-origin request")))
         (t ,@body)))

(defun param (params name)
  (let ((v (cdr (assoc name params :test #'equal))))
    (if (and (stringp v) (string= v "")) nil v)))

(defun space-url (space) (format nil "/s/~a" space))
(defun model-url (space model) (format nil "/s/~a/m/~a" space model))
(defun content-url (space model id) (format nil "/s/~a/m/~a/~a" space model id))

(defcomp ~flash (&key message (kind :ok))
  (if message
      (hsx (div :class (clsx "mb-6 rounded-md border px-4 py-3 text-sm"
                             (if (eq kind :error) "border-danger/40 bg-danger/5 text-danger" "border-ok/40 bg-ok/5 text-ok"))
             message))
      (hsx (<>))))

(defcomp ~errors (&key errors)
  (if errors
      (hsx (div :class "mb-6 rounded-md border border-danger/40 bg-danger/5 px-4 py-3 text-sm text-danger"
             (ul :class "list-disc pl-5"
               (loop :for e :in errors :collect
                 (hsx (li (strong (getf e :field)) " " (getf e :message)))))))
      (hsx (<>))))

(defcomp ~layout (&key space crumbs children)
  (hsx
   (<>
     (header :class "border-b border-line bg-panel"
       (div :class "mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3"
         (nav :class "flex items-center gap-2 text-sm"
           (a :href "/" :class "font-bold tracking-tight text-fg" "koya")
           (when space
             (hsx (<> (span :class "text-muted" "/")
                      (a :href (space-url space) :class "text-fg hover:underline" space))))
           (loop :for (label . href) :in crumbs :collect
             (hsx (<> (span :class "text-muted" "/")
                      (if href
                          (hsx (a :href href :class "text-fg hover:underline" label))
                          (hsx (span :class "text-muted" label)))))))
         (form :method "post" :action "/logout"
           (button :type "submit" :class "btn" "Log out"))))
     (main :class "mx-auto max-w-5xl px-4 py-8"
       (multiple-value-bind (message kind) (take-flash)
         (~flash :message message :kind kind))
       children))))

(defcomp ~status-badge (&key status)
  (let ((class (cond ((string= status "published") "bg-ok/10 text-ok")
                     ((string= status "published+draft") "bg-warn/10 text-warn")
                     (t "bg-line text-muted"))))
    (hsx (span :class (clsx "badge" class) status))))

(defcomp ~empty-state (&key children)
  (hsx (div :class "rounded-md border border-dashed border-line px-6 py-10 text-center text-sm text-muted" children)))
