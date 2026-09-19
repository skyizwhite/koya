(defpackage #:koya-server/document
  (:use #:cl #:hsx)
  (:export #:~document))
(in-package #:koya-server/document)

(defcomp ~document (&key title children)
  (hsx
   (html :lang "ja"
     (head
       (meta :charset "utf-8")
       (meta :name "viewport" :content "width=device-width, initial-scale=1")
       (title (or title "koya"))
       (link :rel "stylesheet" :href "/assets/style/quill.snow.css")
       (link :rel "stylesheet" :href "/assets/style/dist.css")
       (script :src "/assets/js/htmx.min.js" :defer t)
       (script :src "/assets/js/quill/quill.js" :defer t)
       (script :src "/assets/js/koya-editor.js" :defer t))
     (body :class "min-h-screen bg-base text-fg antialiased"
       children))))
