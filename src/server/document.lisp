(defpackage #:koya-server/document
  (:use #:cl #:hsx)
  (:import-from #:koya-server/lib/assets #:asset-url)
  (:export #:~document))
(in-package #:koya-server/document)

(defcomp ~document (&key title children)
  (hsx
   (html :lang "ja"
     (head
       (meta :charset "utf-8")
       (meta :name "viewport" :content "width=device-width, initial-scale=1")
       (title (or title "koya"))
       (link :rel "icon" :type "image/svg+xml" :href (asset-url "icon.svg"))
       (link :rel "stylesheet" :href (asset-url "style/quill.snow.css"))
       (link :rel "stylesheet" :href (asset-url "style/dist.css"))
       (script :src (asset-url "js/htmx.min.js") :defer t)
       (script :src (asset-url "js/quill/quill.js") :defer t)
       (script :src (asset-url "js/qrcode.min.js") :defer t)
       (script :src (asset-url "js/koya-editor.js") :defer t))
     (body :class "flex min-h-screen flex-col bg-base text-fg antialiased"
       children))))
