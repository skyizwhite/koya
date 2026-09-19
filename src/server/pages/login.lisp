(defpackage #:koya-server/pages/login
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/lib/auth #:session-login)
  (:import-from #:koya-server/lib/page #:owner-p #:set-title #:redirect-to #:param #:same-origin-p)
  (:export #:@get #:@post))
(in-package #:koya-server/pages/login)

(defcomp ~login-form (&key error)
  (hsx
   (main :class "mx-auto max-w-sm px-4 py-24"
     (h1 :class "mb-6 text-2xl font-bold tracking-tight" "koya")
     (form :method "post" :action "/login" :class "space-y-4"
       (div
         (label :for "secret" :class "label" "Owner secret")
         (input :type "password" :id "secret" :name "secret" :required t :autofocus t :class "input mt-1.5"))
       (when error (hsx (p :class "text-sm text-danger" error)))
       (button :type "submit" :class "btn btn-primary w-full justify-center" "Log in")))))

(defun @get (params)
  (declare (ignore params))
  (set-title "Log in · koya")
  (if (owner-p)
      (redirect-to "/" 302)
      (hsx (~login-form))))

(defun @post (params)
  (set-title "Log in · koya")
  (cond ((not (same-origin-p))
         (set-response-status 403)
         (hsx (~login-form :error "Cross-origin request rejected")))
        ((session-login (or (param params "secret") ""))
         (redirect-to "/"))
        (t
         (set-response-status 401)
         (hsx (~login-form :error "Wrong secret")))))
