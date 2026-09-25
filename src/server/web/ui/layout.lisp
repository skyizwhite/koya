(defpackage #:koya-server/web/ui/layout
  (:use #:cl #:hsx)
  (:import-from #:jingle
                #:set-response-header #:set-response-status)
  (:import-from #:ningle-actions
                #:defaction)
  (:import-from #:koya-server/web/auth
                #:session-logout)
  (:import-from #:koya-server/web/assets
                #:asset-url)
  (:import-from #:koya-server/web/urls
                #:space-url)
  (:import-from #:koya-server/web/ui/icon
                #:~icon)
  (:import-from #:koya-server/web/ui/toast
                #:~toast #:take-toast)
  (:export #:~layout
           #:~missing
           #:~footer
           #:logout))
(in-package #:koya-server/web/ui/layout)

;;; The frame of every page behind the login: the header with its crumbs, #toast,
;;; and the footer.

;;; The AGPL asks a server that others use over the network to offer them its
;;; source, so every page links to it. The link is the system's :homepage: a fork
;;; that points it at its own repository offers its own source.

(defparameter *version* (asdf:component-version (asdf:find-system "koya-server")))
(defparameter *repository* (asdf:system-homepage (asdf:find-system "koya-server")))

(defcomp ~footer ()
  (hsx
   (footer :class "mx-auto w-full max-w-5xl border-t border-line px-4 py-6 text-xs text-muted"
     (p :class "flex flex-wrap items-center gap-x-3 gap-y-1"
       (span (format nil "koya ~a" *version*))
       (a :href *repository* :class "hover:text-fg hover:underline" "Source code")
       (span "Licensed under the "
             (a :href "https://www.gnu.org/licenses/agpl-3.0.html" :class "hover:text-fg hover:underline"
                "GNU AGPL v3.0")
             " or later")))))

(defcomp ~crumb (&key href label)
  (hsx (span :class "flex min-w-0 max-w-full items-center gap-2 whitespace-nowrap"
         (span :class "text-muted" "/")
         (if href
             (hsx (a :href href :class "max-w-48 truncate text-fg hover:underline sm:max-w-xs" :title label label))
             (hsx (span :class "max-w-48 truncate text-muted sm:max-w-xs" :title label label))))))

;; the header's Log out, on every page
(defaction logout :post (params)
  (declare (ignore params))
  (session-logout)
  (set-response-header :hx-redirect "/login")
  (hsx (<>)))

(defcomp ~layout (&key space crumbs children)
  (hsx
   (<>
     (header :class "border-b border-line bg-panel"
       (div :class "mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3"
         ;; on a narrow screen the crumbs wrap, each with its slash, and a long one
         ;; (a content's label) is cut short; the buttons keep their size
         (nav :class "flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-sm"
           (a :href "/" :class "inline-flex shrink-0 items-center gap-2 font-bold tracking-tight text-fg"
              (img :src (asset-url "icon.svg") :alt "" :width "20" :height "20" :class "h-5 w-5 rounded")
              "koya")
           (when space
             (hsx (~crumb :href (space-url space) :label space)))
           (loop :for (label . href) :in crumbs :collect
             (hsx (~crumb :href href :label label))))
         (div :class "flex shrink-0 items-center gap-2"
           (a :href "/settings" :class "btn" :aria-label "Settings"
              (~icon :name :settings) (span :class "hidden sm:inline" "Settings"))
           (form :hx-post (logout)
             (button :type "submit" :class "btn" :aria-label "Log out"
                     (~icon :name :logout) (span :class "hidden sm:inline" "Log out"))))))
     (main :class "mx-auto w-full max-w-5xl flex-1 px-4 py-8"
       (multiple-value-bind (message kind) (take-toast)
         (hsx (~toast :message message :kind kind)))
       children)
     (~footer))))

(defcomp ~missing (&key what space)
  "The page for a URL that names a WHAT -- a space, a model -- that is not there,
answered 404, inside SPACE's frame when the space itself exists."
  (set-response-status 404)
  (hsx (~layout :space space (h1 :class "text-xl font-bold" (format nil "~a not found" what)))))
