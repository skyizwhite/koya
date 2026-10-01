(defpackage #:koya-server/web/lib/document
  (:use #:cl #:hsx)
  (:import-from #:jingle #:context)
  (:import-from #:koya-server/web/lib/assets #:asset-url)
  (:export #:~document
           #:set-title
           #:page-title))
(in-package #:koya-server/web/lib/document)

(defun set-title (title) (setf (context :title) title))
(defun page-title () (context :title))

(defcomp ~document (&key title children)
  (hsx
   (html :lang "en"
     (head
       (meta :charset "utf-8")
       (meta :name "viewport" :content "width=device-width, initial-scale=1")
       (title (or title "koya"))
       (link :rel "icon" :type "image/svg+xml" :href (asset-url "icon.svg"))
       (link :rel "stylesheet" :href (asset-url "style/quill.snow.css"))
       (link :rel "stylesheet" :href (asset-url "style/dist.css"))
       (script :src (asset-url "js/nomini.js") :defer t)
       (script :src (asset-url "js/quill.min.js") :defer t)
       (script :src (asset-url "js/qrcode.min.js") :defer t)
       (script :src (asset-url "js/koya.js") :defer t))
     (body :class "flex min-h-screen flex-col bg-base text-fg antialiased"
       (div :id "location" :hidden t)
       children))))
