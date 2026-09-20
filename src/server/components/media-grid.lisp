(defpackage #:koya-server/components/media-grid
  (:use #:cl #:hsx)
  (:import-from #:koya-server/db/media
                #:media-id #:media-filename #:media-mime #:media-size #:media-width #:media-height
                #:media-alt #:media-created-at)
  (:import-from #:koya-server/lib/media-store
                #:media-url)
  (:import-from #:koya-server/lib/page
                #:short-time #:~empty-state)
  (:export #:~media-grid
           #:~media-card
           #:human-size))
(in-package #:koya-server/components/media-grid)

;;; Thumbnails of a space's media, shared by the library page and the picker.

(defun human-size (bytes)
  (cond ((< bytes 1024) (format nil "~a B" bytes))
        ((< bytes (* 1024 1024)) (format nil "~,1f KB" (/ bytes 1024.0)))
        (t (format nil "~,1f MB" (/ bytes 1024.0 1024.0)))))

(defun dimensions (media)
  (if (and (media-width media) (media-height media))
      (format nil "~a×~a" (media-width media) (media-height media))
      "?"))

(defcomp ~thumb (&key media)
  (hsx (img :src (media-url media :absolute nil) :alt (media-alt media) :loading "lazy"
            :class "aspect-square w-full rounded-md border border-line bg-panel object-contain")))

(defcomp ~media-card (&key media space)
  "Library card: thumbnail, facts, alt form and delete form."
  (let ((id (media-id media)))
    (hsx
     (li :class "space-y-2 text-sm"
       (~thumb :media media)
       (div :class "truncate font-medium" :title (media-filename media) (media-filename media))
       (div :class "text-xs text-muted"
         (format nil "~a · ~a · ~a" (dimensions media) (human-size (media-size media)) (short-time (media-created-at media))))
       (div :class "flex gap-2"
         (a :href (media-url media :absolute nil) :target "_blank" :rel "noopener" :class "btn" "Preview ↗"))
       (form :method "post" :class "flex gap-2"
         (input :type "hidden" :name "action" :value "alt")
         (input :type "hidden" :name "id" :value id)
         (input :type "text" :name "alt" :value (media-alt media) :placeholder "alt text" :class "input" :aria-label "alt text")
         (button :type "submit" :class "btn" "Save"))
       (form :method "post" :class "text-right"
         (input :type "hidden" :name "action" :value "delete")
         (input :type "hidden" :name "id" :value id)
         (button :type "submit" :class "btn btn-danger"
                 :onclick (format nil "return confirm('Delete ~a?~a')"
                                  (remove #\' (media-filename media))
                                  (let ((n (koya-server/db/media:media-references space id)))
                                    (if (plusp n) (format nil " It is used by ~a content~:p." n) "")))
           "Delete"))))))

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

(defcomp ~media-grid (&key items space (mode :library))
  (if (null items)
      (hsx (~empty-state "No media yet. Upload an image above."))
      (hsx (ul :class (if (eq mode :picker)
                          "grid grid-cols-3 gap-3 sm:grid-cols-4"
                          "grid grid-cols-2 gap-6 sm:grid-cols-3 lg:grid-cols-4")
             (loop :for media :in items :collect
               (if (eq mode :picker)
                   (hsx (~pick-card :media media))
                   (hsx (~media-card :media media :space space))))))))
