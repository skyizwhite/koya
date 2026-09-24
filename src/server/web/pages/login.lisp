(defpackage #:koya-server/web/pages/login
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/auth
                #:session-login #:public-path #:session-owner-p #:local-path-p)
  (:import-from #:koya-server/usecases/auth
                #:login-locked-p #:note-login-failure #:clear-login-failures)
  (:import-from #:lack/request #:request-remote-addr)
  (:import-from #:koya-server/usecases/settings/two-factor #:totp-enabled-p)
  (:import-from #:koya-server/web/assets #:asset-url)
  (:import-from #:koya-server/web/http #:redirect-to #:param)
  (:import-from #:koya-server/web/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~footer)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:export #:@get #:log-in))
(in-package #:koya-server/web/pages/login)

(defcomp ~login-fields (&key error next)
  "The form, which the log-in action draws again with what went wrong."
  (hsx
   (form :id "login" :class "space-y-4"
         :hx-post (log-in) :hx-target "#login" :hx-swap "outerHTML"
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
      (~login-fields :next next))
    (~footer))))

(defun next-path (params)
  "Where the login redirects to: the page that sent the owner here, if it is one of ours."
  (let ((next (param params "next")))
    (and (local-path-p next) next)))

;; where a session comes from
(public-path "/login")

(defun @get (params)
  (set-title "Log in · koya")
  (if (session-owner-p)
      (redirect-to (or (next-path params) "/") 302)
      (hsx (~login-page :next (next-path params)))))

;; The one action reachable without a session: it is where a session comes from.
;; The actions guard still asks for htmx and this server's origin, which keeps
;; another site from logging a browser in.
(defaction log-in :post (params)
  (let ((address (request-remote-addr ningle:*request*))
        (next (next-path params)))
    (flet ((refuse (status error)
             (set-response-status status)
             (hsx (~login-fields :error error :next next)))
           (go-on ()
             (set-response-header :hx-redirect (or next "/"))
             (hsx (<>))))
      (cond ((session-owner-p) (go-on))
            ;; 403, not 429: Woo has no status line for 429 and fails to write the response
            ((login-locked-p address) (refuse 403 "Too many attempts. Wait a few minutes and try again."))
            ((eq (session-login (or (param params "secret") "") (param params "code")) t)
             (clear-login-failures address)
             (go-on))
            (t
             (note-login-failure address)
             ;; one message for both factors: not saying which one was wrong
             (refuse 401 (if (totp-enabled-p) "Wrong secret or one-time code" "Wrong secret")))))))

(public-path (log-in))
