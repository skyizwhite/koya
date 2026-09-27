(defpackage #:koya-server/web/ui/media/grid
  (:use #:cl #:hsx)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-filename #:media-width #:media-height #:media-alt #:+max-upload-bytes+)
  (:import-from #:koya-server/usecases/media #:upload-limit-message)
  (:import-from #:koya-server/web/ui/toast #:~toast)
  (:import-from #:koya-server/web/lib/presenters #:media-url)
  (:import-from #:koya-server/web/ui/elements #:~empty-state)
  (:export #:~media-grid
           #:~upload-limit
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

(defcomp ~upload-limit ()
  (hsx (template :data-upload-limit (princ-to-string +max-upload-bytes+)
         (~toast :message (upload-limit-message) :kind :error))))

(defcomp ~thumb (&key media)
  (hsx (img :src (media-url media :absolute nil) :alt (media-alt media) :loading "lazy" :decoding "async"
            :class "aspect-square w-full rounded-md border border-line bg-panel object-contain")))

(defcomp ~pick-card (&key media)
  (hsx
   (li
     (button :type "button" :class "w-full space-y-1 rounded-md p-1 text-left text-xs hover:bg-accent/5"
             :data-pick-id (media-id media)
             :data-pick-url (media-url media :absolute nil)
             :data-pick-alt (media-alt media)
             :data-pick-name (media-filename media)
       (~thumb :media media)
       (div :class "truncate" :title (media-filename media) (media-filename media))
       (div :class "text-muted" (dimensions media))))))

(defcomp ~pick-cards (&key items more)
  (hsx
   (<> (loop :for media :in items :collect (hsx (~pick-card :media media)))
       (when more
         (hsx (li :class "col-span-full py-2 text-center text-xs text-muted"
                  :hx-get more :hx-trigger "revealed" :hx-swap "outerHTML"
                "Loading…"))))))

(defcomp ~media-grid (&key items more)
  (if (null items)
      (hsx (~empty-state "No media yet. Upload an image above."))
      (hsx (ul :class "grid grid-cols-3 gap-3 sm:grid-cols-4"
             (~pick-cards :items items :more more)))))
