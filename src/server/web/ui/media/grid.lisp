(defpackage #:koya-server/web/ui/media/grid
  (:use #:cl #:hsx)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-filename #:media-width #:media-height #:media-alt)
  (:import-from #:koya-server/web/lib/presenters #:media-url)
  (:import-from #:koya-server/web/ui/elements #:~empty-state)
  (:import-from #:koya-server/web/lib/binds #:ask)
  (:export #:~media-grid
           #:~pick-cards
           #:~thumb
           #:dimensions
           #:human-size))
(in-package #:koya-server/web/ui/media/grid)

(defun human-size (bytes)
  (cond ((< bytes 1024) (format nil "~a B" bytes))
        ((< bytes (* 1024 1024)) (format nil "~,1f KB" (/ bytes 1024.0)))
        (t (format nil "~,1f MB" (/ bytes 1024.0 1024.0)))))

(defun dimensions (media)
  (if (and (media-width media) (media-height media))
      (format nil "~a×~a" (media-width media) (media-height media))
      "?"))

(defcomp ~thumb (&key media)
  (hsx (img :src (media-url media :absolute nil) :alt (media-alt media) :loading "lazy" :decoding "async"
            :class "aspect-square w-full rounded-md border border-line bg-panel object-contain")))

(defcomp ~pick-card (&key media)
  (hsx
   (li
     (button :type "button" :class "w-full space-y-1 rounded-md p-1 text-left text-xs ring-accent hover:bg-accent/5"
             :data-pick-id (media-id media)
             :data-pick-url (media-url media :absolute nil)
             :data-pick-alt (media-alt media)
             :data-pick-name (media-filename media)
             :n-on-click "pick(this)" :n-bind-class.ring-2 "has(this.dataset.pickId)" :n-bind-ariapressed "many ? String(has(this.dataset.pickId)) : null"
       (~thumb :media media)
       (div :class "truncate" :title (media-filename media) (media-filename media))
       (div :class "text-muted" (dimensions media))))))

(defcomp ~pick-cards (&key items more)
  (hsx
   (<> (loop :for media :in items :collect (hsx (~pick-card :media media)))
       (when more
         (hsx (li :id more :class "col-span-full py-2 text-center text-xs text-muted"
                  :n-on-init "koya.reveal(e)" :n-on-revealed (ask more)
                "Loading…"))))))

(defcomp ~media-grid (&key items more)
  (if (null items)
      (hsx (~empty-state "No media yet. Upload an image above."))
      (hsx (ul :class "grid grid-cols-3 gap-3 sm:grid-cols-4"
             (~pick-cards :items items :more more)))))
