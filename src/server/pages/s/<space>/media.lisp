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
  (:import-from #:koya-server/lib/forms #:form-values)
  (:export #:@get #:@post #:media-page-url))
(in-package #:koya-server/pages/s/<space>/media)

(defparameter +page-size+ 20)

(defun media-page-url (space) (format nil "~a/media" (space-url space)))

(defun ensure-space (params)
  (let ((name (path-param params :space)))
    (and (find-space name) name)))

(defun page-link (page search)
  (format nil "?page=~a~@[&q=~a~]" page (and search (plusp (length search)) (quri:url-encode search))))

(defun library-url (space &key search (page 1))
  "The library with the search and page it is being read at."
  (format nil "~a~a" (media-page-url space) (page-link page search)))

(defparameter +bulk-form+ "media-bulk"
  "The selection form's id: the boxes are on the cards and join it by their form
attribute, because the card already holds a form and forms do not nest.")

(defun page-number (params)
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

(defcomp ~selection (&key space search page)
  "The selection bar. Select all sits outside it, since the bar itself is hidden
until something is selected."
  (hsx
   (div :class "mb-4 flex flex-wrap items-center gap-3"
     (label :class "flex items-center gap-2 text-sm text-muted"
       (input :type "checkbox" :data-bulk-all t :form +bulk-form+)
       "Select all on this page")
     (form :method "post" :id +bulk-form+ :data-bulk t
       (input :type "hidden" :name "q" :value (or search ""))
       (input :type "hidden" :name "page" :value (princ-to-string page))
       (div :data-bulk-bar t :hidden t :class "flex flex-wrap items-center gap-2 text-sm"
         (span :data-bulk-count t :class "mr-1 text-muted" "0 selected")
         (button :type "submit" :name "action" :value "delete-selected" :class "btn btn-danger"
                 :data-confirm "Delete the selected files?"
                 :data-bulk-confirm "Delete the selection ({n})? This cannot be undone."
           (~icon :name :delete) "Delete"))))))

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
       (when items
         (hsx (~selection :space space :search search :page page)))
       (~media-grid :items items :space space :bulk-form +bulk-form+)
       (~media-preview-dialog)
       (when (> pages 1)
         (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                (when (> page 1)
                  (hsx (a :href (page-link (1- page) search) :class "btn" (~icon :name :prev) "Previous")))
                (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                (when (< page pages)
                  (hsx (a :href (page-link (1+ page) search) :class "btn" "Next" (~icon :name :next)))))))))))

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
               (handler-case
                   (progn
                     (when media (remove-media media))
                     (set-flash (if media "Media deleted." "Media not found.") (if media :ok :error)))
                 (api-error (e) (set-flash (api-error-message e) :error)))
               (redirect-to (media-page-url space))))
            ((equal action "delete-selected")
             ;; one at a time: a file in use is refused, the rest still go
             (let ((ids (form-values params "id"))
                   (back (library-url space :search (param params "q") :page (page-number params)))
                   (done 0) (failed 0) (message nil))
               (cond ((null ids) (set-flash "Nothing was selected." :error))
                     (t (dolist (id ids)
                          (handler-case
                              (let ((media (find-media space id)))
                                (cond ((null media)
                                       (incf failed)
                                       (unless message (setf message "one was gone already")))
                                      (t (remove-media media) (incf done))))
                            ;; every condition, not only the store's own: a file
                            ;; that will not leave the disk must not take the
                            ;; selection down with it
                            (api-error (e)
                              (incf failed)
                              (unless message (setf message (api-error-message e))))
                            (error (e)
                              (incf failed)
                              (unless message (setf message (princ-to-string e))))))
                        (set-flash (if (zerop failed)
                                       (format nil "Deleted ~a file~:p." done)
                                       (format nil "Deleted ~a of ~a; ~a could not be~@[: ~a~]"
                                               done (+ done failed) failed message))
                                   (if (plusp failed) :error :ok))))
               (redirect-to back)))
            (t (set-response-status 400) (hsx (~layout :space space (p "Unknown action"))))))))
