(defpackage #:koya-server/web/ui/media/grid
  (:use #:cl #:hsx)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-filename #:media-width #:media-height #:media-alt #:+max-upload-bytes+)
  (:import-from #:koya-server/usecases/media/library #:upload-limit-message)
  (:import-from #:koya-server/web/ui/toast #:~toast)
  (:import-from #:koya-server/web/presenters #:media-url)
  (:import-from #:koya-server/web/ui/elements #:~empty-state)
  (:export #:~media-grid
           #:~upload-limit
           #:~pick-cards
           #:~thumb
           #:dimensions
           #:human-size))
(in-package #:koya-server/web/ui/media/grid)

;;; What the library page and the picker share: a thumbnail, its size in words,
;;; the limit on an upload, and the picker's grid. The library's own cards and
;;; preview are on its page.

(defun human-size (bytes)
  (cond ((< bytes 1024) (format nil "~a B" bytes))
        ((< bytes (* 1024 1024)) (format nil "~,1f KB" (/ bytes 1024.0)))
        (t (format nil "~,1f MB" (/ bytes 1024.0 1024.0)))))

(defun dimensions (media)
  (if (and (media-width media) (media-height media))
      (format nil "~a×~a" (media-width media) (media-height media))
      "?"))

(defcomp ~upload-limit ()
  "Put in an upload form: what koya-editor.js checks the chosen files against before
they are sent, and the toast it shows when they are too large. The server's 413
would not do: it answers before the body is read and closes the connection, and
a browser still sending takes that for a reset and shows nothing."
  (hsx (template :data-upload-limit (princ-to-string +max-upload-bytes+)
         (~toast :message (upload-limit-message) :kind :error))))

(defcomp ~thumb (&key media)
  (hsx (img :src (media-url media :absolute nil) :alt (media-alt media) :loading "lazy" :decoding "async"
            :class "aspect-square w-full rounded-md border border-line bg-panel object-contain")))

(defcomp ~pick-card (&key media)
  "Picker card: one button carrying everything the page needs to use the file."
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
  "The picker's cards, and when MORE -- the URL of the next ones -- the row that
fetches them as it scrolls into view and is replaced by them."
  (hsx
   (<> (loop :for media :in items :collect (hsx (~pick-card :media media)))
       (when more
         (hsx (li :class "col-span-full py-2 text-center text-xs text-muted"
                  :hx-get more :hx-trigger "revealed" :hx-swap "outerHTML"
                "Loading…"))))))

(defcomp ~media-grid (&key items more)
  "The picker's grid."
  (if (null items)
      (hsx (~empty-state "No media yet. Upload an image above."))
      (hsx (ul :class "grid grid-cols-3 gap-3 sm:grid-cols-4"
             (~pick-cards :items items :more more)))))
