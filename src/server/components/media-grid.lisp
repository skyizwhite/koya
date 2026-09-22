(defpackage #:koya-server/components/media-grid
  (:use #:cl #:hsx)
  (:import-from #:koya-server/db/media
                #:media-id #:media-filename #:media-mime #:media-size #:media-width #:media-height
                #:media-alt #:media-created-at)
  (:import-from #:koya-server/lib/media-store
                #:media-url)
  (:import-from #:koya-server/lib/page
                #:short-time #:~empty-state #:~icon)
  (:export #:~media-grid
           #:~media-card
           #:~media-preview-dialog
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

(defun delete-confirmation (media references)
  "What the owner is asked before a file goes. A file REFERENCES contents still
use cannot go (the server refuses), so the question becomes an explanation."
  (if (plusp (or references 0))
      (format nil "~a is used by ~a content~:p and cannot be deleted until they stop using it. Remove it from them first."
              (media-filename media) references)
      (format nil "Delete ~a?" (media-filename media))))

(defcomp ~media-card (&key media space references bulk-form)
  "Library card: the picture and nothing else. Its name and facts are in the
preview dialog the thumbnail opens, along with everything that can be done to
the file; only Delete is on the card, over its corner. REFERENCES is how many
contents mention the file (shown in the confirmation). BULK-FORM is the id of the
page's selection form: the box belongs to it through its form attribute, because
a form cannot be nested inside the card's own."
  (declare (ignore space))
  (let ((id (media-id media)))
    (hsx
     (li :class "relative"
       (when bulk-form
         (hsx (input :type "checkbox" :name "id" :value id :form bulk-form :data-bulk-item t
                     :class "absolute left-1 top-1 z-10 h-4 w-4 cursor-pointer"
                     :aria-label (format nil "Select ~a" (media-filename media)))))
       ;; the whole thumbnail is the preview button, so the card needs no other
       (button :type "button" :class "block w-full cursor-zoom-in"
               :data-preview-src (media-url media :absolute nil)
               :data-preview-alt (media-alt media)
               :data-preview-name (media-filename media)
               :data-preview-meta (format nil "~a · ~a · ~a" (dimensions media) (human-size (media-size media))
                                          (short-time (media-created-at media)))
               :data-preview-id id
               :data-preview-references (or references 0)
               :data-preview-confirm (delete-confirmation media references)
               :title (media-filename media)
               :aria-label (format nil "Preview ~a" (media-filename media))
         (~thumb :media media))
       ;; a file in use keeps its button, disabled, so the owner sees why it stays
       (form :method "post" :class "absolute right-1 top-1"
         (input :type "hidden" :name "action" :value "delete")
         (input :type "hidden" :name "id" :value id)
         ;; the confirmation text is data, not inline script: koya-editor.js asks
         (button :type "submit" :class "btn btn-danger btn-icon"
                 :disabled (plusp (or references 0))
                 :title (if (plusp (or references 0)) (delete-confirmation media references) nil)
                 :data-confirm (delete-confirmation media references)
                 :aria-label (format nil "Delete ~a" (media-filename media))
           (~icon :name :delete)))))))

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

(defcomp ~media-grid (&key items space (mode :library) bulk-form)
  (if (null items)
      (hsx (~empty-state "No media yet. Upload an image above."))
      (let ((references (and (eq mode :library)
                             (koya-server/db/media:media-reference-counts space (mapcar #'media-id items)))))
        (hsx (ul :class (if (eq mode :picker)
                            "grid grid-cols-3 gap-3 sm:grid-cols-4"
                            ;; pictures only, so they can be small and many
                            "grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6")
               (loop :for media :in items :collect
                 (if (eq mode :picker)
                     (hsx (~pick-card :media media))
                     (hsx (~media-card :media media :space space :bulk-form bulk-form
                                       :references (gethash (media-id media) references 0))))))))))

(defcomp ~media-preview-dialog ()
  "One dialog per page; [data-preview-src] buttons fill and open it (koya-editor.js).
The file's alt text and its Delete live here rather than on every card. Both
forms post to the page the dialog is on, which is the media library."
  (hsx
   (dialog :id "media-preview" :class "koya-dialog max-w-3xl"
     (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
       (div :class "min-w-0"
         (div :class "truncate font-semibold" :data-preview-title t "")
         (div :class "text-xs text-muted" :data-preview-caption t ""))
       (div :class "flex shrink-0 items-center gap-2"
         (form :method "post"
           (input :type "hidden" :name "action" :value "delete")
           (input :type "hidden" :name "id" :value "" :data-preview-id t)
           ;; the confirmation starts generic and is replaced with the open file's
           ;; own, which also makes the button one koya-editor.js binds at load
           (button :type "submit" :class "btn btn-danger btn-icon" :data-preview-delete t
                   :data-confirm "Delete this file?" :aria-label "Delete"
             (~icon :name :delete)))
         (button :type "button" :class "btn btn-icon" :data-dialog-close t :aria-label "Close" (~icon :name :close))))
     (div :class "flex max-h-[65vh] items-center justify-center bg-fg/5 p-4"
       (img :src "" :alt "" :class "max-h-[60vh] max-w-full object-contain" :data-preview-image t))
     (form :method "post" :class "flex items-center gap-2 border-t border-line px-4 py-3"
       (input :type "hidden" :name "action" :value "alt")
       (input :type "hidden" :name "id" :value "" :data-preview-id t)
       (input :type "text" :name "alt" :value "" :placeholder "alt text" :class "input" :aria-label "alt text"
              :data-preview-alt-input t)
       (button :type "submit" :class "btn btn-icon" :aria-label "Save alt text" (~icon :name :check))))))
