(defpackage #:koya-server/pages/s/<space>/media
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/media #:list-media #:count-media #:find-media #:update-media)
  (:import-from #:koya-server/lib/media-store #:store-upload #:remove-media)
  (:import-from #:koya-server/lib/http #:path-param #:uploaded-files #:api-error #:api-error-message)
  (:import-from #:koya-server/lib/page
                #:with-owner #:with-owner-post #:set-title #:param #:set-flash #:redirect-to
                #:~layout #:~icon #:space-url)
  (:import-from #:koya-server/components/media-grid #:~media-grid #:~media-preview-dialog)
  (:export #:@get #:@post #:media-page-url))
(in-package #:koya-server/pages/s/<space>/media)

(defparameter +page-size+ 48)

(defun media-page-url (space) (format nil "~a/media" (space-url space)))

(defun ensure-space (params)
  (let ((name (path-param params :space)))
    (and (find-space name) name)))

(defun page-link (page search)
  (format nil "?page=~a~@[&q=~a~]" page (and search (plusp (length search)) (quri:url-encode search))))

(defun page-number (params)
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

(defcomp ~media-page (&key space search page)
  (let* ((total (count-media space :search search))
         (pages (max 1 (ceiling total +page-size+)))
         (page (min page pages))
         (items (list-media space :search search :limit +page-size+ :offset (* (1- page) +page-size+))))
    (hsx
     (~layout :space space :crumbs (list (cons "Media" nil))
       (div :class "mb-6 flex flex-wrap items-center justify-between gap-4"
         (h1 :class "text-2xl font-bold" "Media"
           (span :class "ml-3 text-base font-normal text-muted" (format nil "~a file~:p" total)))
         (form :method "get" :class "flex gap-2"
           (input :type "search" :name "q" :value (or search "") :placeholder "Search file names" :class "input")
           (button :type "submit" :class "btn btn-icon" :aria-label "Search" (~icon :name :search))))
       ;; the picker's upload row (see actions/media-picker): the button opens the
       ;; file picker and the files go up as soon as they are chosen. alt text is
       ;; written afterwards, in the preview dialog.
       (form :method "post" :enctype "multipart/form-data"
             :class "mb-8 flex flex-wrap items-center gap-3 rounded-md border border-dashed border-line p-3 text-sm"
         (input :type "hidden" :name "action" :value "upload")
         (label :class "btn" (~icon :name :upload) "Upload"
           (input :type "file" :name "file" :accept "image/png,image/jpeg,image/gif,image/webp"
                  :multiple t :class "hidden" :data-submit-on-change t))
         (span :class "text-muted" "PNG, JPEG, GIF or WebP, several at once."))
       (~media-grid :items items :space space)
       (~media-preview-dialog)
       (when (> pages 1)
         (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                (if (> page 1)
                    (hsx (a :href (page-link (1- page) search) :class "btn" (~icon :name :prev) "Previous"))
                    (hsx (<>)))
                (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                (if (< page pages)
                    (hsx (a :href (page-link (1+ page) search) :class "btn" "Next" (~icon :name :next)))
                    (hsx (<>))))))))))

(defun @get (params)
  (with-owner
    (let ((space (ensure-space params)))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t (set-title (format nil "Media · ~a · koya" space))
               (hsx (~media-page :space space :search (param params "q") :page (page-number params))))))))

(defun @post (params)
  (with-owner-post
    (let ((space (ensure-space params))
          (action (param params "action")))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            ((equal action "upload")
             (let ((files (uploaded-files params "file"))
                   (alt (or (param params "alt") "")))
               (handler-case
                   (progn
                     (when (null files) (set-flash "Choose at least one image." :error)
                           (return-from @post (redirect-to (media-page-url space))))
                     (dolist (file files)
                       (store-upload space (first file) :filename (second file) :alt alt))
                     (set-flash (format nil "Uploaded ~a file~:p." (length files))))
                 (api-error (e) (set-flash (api-error-message e) :error)))
               (redirect-to (media-page-url space))))
            ((equal action "alt")
             (let ((media (find-media space (or (param params "id") ""))))
               (when media (update-media space (koya-server/db/media:media-id media) :alt (or (param params "alt") "")))
               (set-flash (if media "alt text saved." "Media not found.") (if media :ok :error))
               (redirect-to (media-page-url space))))
            ((equal action "delete")
             (let ((media (find-media space (or (param params "id") ""))))
               (when media (remove-media media))
               (set-flash (if media "Media deleted." "Media not found.") (if media :ok :error))
               (redirect-to (media-page-url space))))
            (t (set-response-status 400) (hsx (~layout :space space (p "Unknown action"))))))))
