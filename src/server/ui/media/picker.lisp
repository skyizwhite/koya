(defpackage #:koya-server/ui/media/picker
  (:use #:cl #:hsx)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/media #:list-media)
  (:import-from #:koya-server/features/media/library #:store-uploads)
  (:import-from #:koya-server/lib/http #:uploaded-files #:api-error #:api-error-message #:param)
  (:import-from #:koya-server/ui/icon #:~icon)
  (:import-from #:koya-server/ui/media/grid #:~media-grid)
  (:export #:media-picker
           #:media-picker-upload
           #:~media-picker-dialog))
(in-package #:koya-server/ui/media/picker)

;;; The media picker: a <dialog> on the editor page whose body is fetched from
;;; these actions with HTMX, so the same grid serves :media fields and Quill's
;;; image button. Selecting a card is handled in koya-editor.js. The owner
;;; session and same-origin checks are *actions-auth-middleware*'s.

(defparameter +picker-size+ 24)

(defcomp ~picker-body (&key space search error)
  (hsx
   (div :id "media-picker-body" :class "space-y-4"
     (form :hx-get (media-picker :space space) :hx-target "#media-picker-body" :hx-swap "outerHTML"
           :hx-trigger "input changed delay:300ms from:'find input', submit" :class "flex gap-2"
       (input :type "search" :name "q" :value (or search "") :placeholder "Search file names" :class "input" :aria-label "Search"))
     (form :hx-post (media-picker-upload :space space) :hx-target "#media-picker-body" :hx-swap "outerHTML"
           :hx-encoding "multipart/form-data" :hx-trigger "change from:'find input[type=file]'"
           ;; htmx aborts a request after 60s by default; a 20 MB upload may need longer
           :hx-config "timeout:0"
           :class "flex flex-wrap items-center gap-3 rounded-md border border-dashed border-line p-3 text-sm"
       (label :class "btn" (~icon :name :upload) "Upload…"
         (input :type "file" :name "file" :accept "image/png,image/jpeg,image/gif,image/webp" :multiple t :class "hidden"))
       (span :class "text-muted" "PNG, JPEG, GIF or WebP. Uploaded files are added to the library.")
       (when error (hsx (span :class "text-danger" error))))
     (~media-grid :items (list-media space :search search :limit +picker-size+)))))

(defun forbidden (message)
  (set-response-status 403)
  (hsx (div :id "media-picker-body" :class "text-sm text-danger" message)))

(defun picker-space (params)
  (let ((space (param params "space")))
    (and space (find-space space) space)))

(defaction media-picker :get (params)
  (cond ((null (picker-space params)) (forbidden "Unknown space."))
        (t (hsx (~picker-body :space (picker-space params) :search (param params "q"))))))

(defaction media-picker-upload :post (params)
  (cond ((null (picker-space params)) (forbidden "Unknown space."))
        (t (let ((space (picker-space params))
                 (files (uploaded-files params "file")))
             (handler-case
                 (progn (store-uploads space files)
                        (hsx (~picker-body :space space)))
               (api-error (e)
                 (hsx (~picker-body :space space :error (api-error-message e)))))))))

(defcomp ~media-picker-dialog (&key space)
  "The (initially empty) dialog. koya-editor.js loads the body from data-picker-url on open."
  (hsx
   (dialog :id "media-picker" :data-picker-url (media-picker :space space) :class "koya-dialog koya-dialog-wide max-w-3xl"
     (div :class "flex items-center justify-between border-b border-line px-4 py-3"
       (h2 :class "font-semibold" "Media")
       (button :type "button" :class "btn btn-icon" :data-dialog-close t :aria-label "Close" (~icon :name :close)))
     ;; loaded into as a whole: an error fragment may replace #media-picker-body
     (div :id "media-picker-content" :class "max-h-[70vh] overflow-y-auto p-4"
       (div :id "media-picker-body" :class "text-sm text-muted" "Loading…")))))
