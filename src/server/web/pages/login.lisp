(defpackage #:koya-server/web/pages/login
  (:use #:cl #:hsx)
  (:import-from #:jingle
                #:set-response-status)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/lib/auth
                #:session-login #:public-path #:session-owner-p #:local-path-p)
  (:import-from #:koya-server/usecases/settings #:totp-enabled-p)
  (:import-from #:koya-server/usecases/auth #:owner-secret-long-enough-p #:+min-secret-length+)
  (:import-from #:koya-server/web/lib/assets #:asset-url)
  (:import-from #:koya-server/web/lib/http #:redirect-to #:param)
  (:import-from #:koya-server/web/lib/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~footer)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/elements #:~go-to)
  (:import-from #:koya-server/web/lib/binds #:posts)
  (:export #:@get #:log-in))
(in-package #:koya-server/web/pages/login)

(defcomp ~short-secret ()
  (hsx
   (div :id "login" :class "space-y-2 text-sm"
     (p :class "text-danger"
       (format nil "Logging in is off: KOYA_SECRET is shorter than ~a characters." +min-secret-length+))
     (p "Set a longer one, such as the output of "
        (code "openssl rand -hex 32")
        ", and restart the server. Nothing else changes."))))

(defcomp ~login-fields (&key error next)
  (hsx
   (form :id "login" :class "space-y-4"
         :nm-bind (posts (log-in))
     (when next (hsx (input :type "hidden" :name "next" :value next)))
     (div
       (label :for "secret" :class "label" "Owner secret")
       (input :type "password" :id "secret" :name "secret" :required t :autofocus t :class "input mt-1.5"))
     (when (totp-enabled-p)
       (hsx (div
              (label :for "code" :class "label" "One-time code")
              (input :type "text" :id "code" :name "code" :inputmode "numeric" :autocomplete "one-time-code"
                     :pattern "[0-9 ]*" :required t :class "input mt-1.5"))))
     (when error (hsx (p :class "text-sm text-danger" error)))
     (button :type "submit" :class "btn btn-primary w-full justify-center" (~icon :name :login) "Log in"))))

(defcomp ~login-page (&key next)
  (hsx
   (<>
    (main :class "mx-auto w-full max-w-sm flex-1 px-4 py-24"
      (h1 :class "mb-6 flex items-center gap-3 text-2xl font-bold tracking-tight"
        (img :src (asset-url "icon.svg") :alt "" :width "32" :height "32" :class "h-8 w-8 rounded-md")
        "koya")
      (if (owner-secret-long-enough-p)
          (hsx (~login-fields :next next))
          (hsx (~short-secret))))
    (~footer))))

(defun next-path (params)
  (let ((next (param params "next")))
    (and (local-path-p next) next)))

(public-path "/login")

(defun @get (params)
  (set-title "Log in · koya")
  (if (session-owner-p)
      (redirect-to (or (next-path params) "/") 302)
      (hsx (~login-page :next (next-path params)))))

(defaction log-in :post (params)
  (let ((next (next-path params)))
    (flet ((refuse (status error)
             (set-response-status status)
             (hsx (~login-fields :error error :next next)))
           (go-on ()
             (hsx (~go-to :url (or next "/")))))
      (if (session-owner-p)
          (go-on)
          (case (session-login (or (param params "secret") "") (param params "code"))
            ((t) (go-on))
            (:short-secret (set-response-status 403) (hsx (~short-secret)))
            (t (refuse 401 (if (totp-enabled-p) "Wrong secret or one-time code" "Wrong secret"))))))))

(public-path (log-in))
