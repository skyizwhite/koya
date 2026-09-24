(defpackage #:koya-server/pages/s/<space>/media
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/media
                #:list-media #:count-media #:find-media #:update-media #:media-reference-counts
                #:media-id #:media-filename #:media-size #:media-alt #:media-created-at)
  (:import-from #:koya-server/lib/media-store #:store-upload #:remove-media #:media-url)
  (:import-from #:koya-server/lib/http #:path-param #:uploaded-files #:api-error #:api-error-message)
  (:import-from #:koya-server/lib/page
                #:with-owner #:set-title #:param #:short-time
                #:~layout #:~icon #:~empty-state #:~flash-oob #:action-refusal #:space-url)
  (:import-from #:koya-server/components/media-grid #:~thumb #:dimensions #:human-size)
  (:import-from #:koya-server/lib/forms #:form-values)
  (:export #:@get #:media-page-url
           #:upload-media #:delete-media-action #:delete-selected-media #:preview-media #:save-alt))
(in-package #:koya-server/pages/s/<space>/media)

;;; The media library. The search and the page are the URL's, so moving between
;;; them is a page load; what is done to the files is an action answered in place:
;;; #library -- the count, the upload row, the selection and the grid -- is drawn
;;; again at the search and page it was read at. The preview dialog is drawn by
;;; the server for the file it opens.

(defparameter +page-size+ 20)

(defun media-page-url (space) (format nil "~a/media" (space-url space)))

(defun page-link (page search)
  (render-uri (make-uri :query `(("page" . ,page) ,@(and search (plusp (length search)) `(("q" . ,search)))))))

(defparameter +bulk-form+ "media-bulk"
  "The selection form's id: the boxes are on the cards and join it by their form
attribute, because the card already holds a form and forms do not nest.")

(defun page-number (params)
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

(defun delete-confirmation (media references)
  "What is asked before a file goes; with REFERENCES it cannot go, so the question
becomes the reason."
  (if (plusp (or references 0))
      (format nil "~a is used by ~a content~:p and cannot be deleted until they stop using it. Remove it from them first."
              (media-filename media) references)
      (format nil "Delete ~a?" (media-filename media))))

(defcomp ~media-card (&key space media references search page)
  "The picture, which opens the preview, a Delete over its corner, and a box that
joins the selection form."
  (let ((id (media-id media))
        (in-use (plusp (or references 0))))
    (hsx
     (li :class "relative"
       (input :type "checkbox" :name "id" :value id :form +bulk-form+ :data-bulk-item t
              :class "absolute left-1 top-1 z-10 h-4 w-4 cursor-pointer"
              :aria-label (format nil "Select ~a" (media-filename media)))
       (button :type "button" :class "block w-full cursor-zoom-in"
               :hx-get (preview-media :space space :id id :q (or search "") :page page)
               :hx-target "#media-preview" :hx-swap "outerHTML"
               :title (media-filename media)
               :aria-label (format nil "Preview ~a" (media-filename media))
         (~thumb :media media))
       ;; a file in use keeps its button, disabled, so the owner sees why it stays
       (form :class "absolute right-1 top-1"
             :hx-post (delete-media-action :space space :q (or search "") :page page)
             :hx-target "#library" :hx-swap "outerHTML"
             :hx-confirm (delete-confirmation media references)
         (input :type "hidden" :name "id" :value id)
         (button :type "submit" :class "btn btn-danger btn-icon"
                 :disabled in-use
                 :title (and in-use (delete-confirmation media references))
                 :aria-label (format nil "Delete ~a" (media-filename media))
           (~icon :name :delete)))))))

(defcomp ~library (&key space search page)
  (let* ((total (count-media space :search search))
         (pages (max 1 (ceiling total +page-size+)))
         (page (min page pages))
         (items (list-media space :search search :limit +page-size+ :offset (* (1- page) +page-size+)))
         (references (media-reference-counts space (mapcar #'media-id items)))
         (q (or search "")))
    (hsx
     (div :id "library"
       (div :class "mb-6 flex flex-wrap items-center justify-between gap-4"
         (h1 :class "text-2xl font-bold" "Media"
           (span :class "ml-3 text-base font-normal text-muted" (format nil "~a file~:p" total)))
         (form :method "get" :action (media-page-url space) :class "flex gap-2"
           (input :type "search" :name "q" :value q :placeholder "Search file names" :class "input")
           (button :type "submit" :class "btn btn-icon" :aria-label "Search" (~icon :name :search))))
       ;; the files go up as soon as they are chosen, as in the picker
       ;; (actions/media-picker); alt text is written afterwards, in the preview
       (form :hx-post (upload-media :space space :q q :page page)
             :hx-target "#library" :hx-swap "outerHTML"
             :hx-encoding "multipart/form-data" :hx-trigger "change from:'find input[type=file]'"
             ;; htmx aborts a request after 60s by default; a 20 MB upload may need longer
             :hx-config "timeout:0"
             :class "mb-8 flex flex-wrap items-center gap-3 rounded-md border border-dashed border-line p-3 text-sm"
         (label :class "btn" (~icon :name :upload) "Upload"
           (input :type "file" :name "file" :accept "image/png,image/jpeg,image/gif,image/webp"
                  :multiple t :class "hidden"))
         (span :class "text-muted" "PNG, JPEG, GIF or WebP, several at once."))
       (if (null items)
           (hsx (~empty-state (if (plusp (length q)) "No file matches." "No media yet. Upload an image above.")))
           (hsx
            (<>
              ;; Select all sits outside the bar, which is hidden until something is selected
              (div :class "mb-4 flex flex-wrap items-center gap-3"
                (label :class "flex items-center gap-2 text-sm text-muted"
                  (input :type "checkbox" :data-bulk-all t :form +bulk-form+)
                  "Select all on this page")
                (form :id +bulk-form+ :data-bulk t
                      :hx-post (delete-selected-media :space space :q q :page page)
                      :hx-target "#library" :hx-swap "outerHTML"
                      :hx-confirm "Delete the selected files? This cannot be undone."
                  (div :data-bulk-bar t :hidden t :class "flex flex-wrap items-center gap-2 text-sm"
                    (span :data-bulk-count t :class "mr-1 text-muted" "0 selected")
                    (button :type "submit" :class "btn btn-danger" (~icon :name :delete) "Delete"))))
              (ul :class "grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6"
                (loop :for media :in items :collect
                  (hsx (~media-card :space space :media media :search search :page page
                                    :references (gethash (media-id media) references 0))))))))
       (when (> pages 1)
         (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                (when (> page 1)
                  (hsx (a :href (page-link (1- page) search) :class "btn" (~icon :name :prev) "Previous")))
                (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                (when (< page pages)
                  (hsx (a :href (page-link (1+ page) search) :class "btn" "Next" (~icon :name :next)))))))))))

(defcomp ~media-preview-dialog (&key space media references search page oob)
  "The picture large, its alt text and Delete. Empty and closed until a card asks
for a file; drawn for it, it opens itself (data-show-modal, koya-editor.js)."
  (let ((in-use (and media (plusp (or references 0)))))
    (hsx
     (dialog :id "media-preview" :closedby "any" :data-show-modal (and media t)
             :hx-swap-oob (and oob "true")
             :class "koya-dialog koya-dialog-wide max-w-3xl"
       (when media
         (hsx
          (<>
            (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
              (div :class "min-w-0"
                (div :class "truncate font-semibold" (media-filename media))
                (div :class "text-xs text-muted"
                  (format nil "~a · ~a · ~a" (dimensions media) (human-size (media-size media))
                          (short-time (media-created-at media)))))
              (div :class "flex shrink-0 items-center gap-2"
                (form :hx-post (delete-media-action :space space :q (or search "") :page page)
                      :hx-target "#library" :hx-swap "outerHTML"
                      :hx-confirm (delete-confirmation media references)
                  (input :type "hidden" :name "id" :value (media-id media))
                  (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete"
                          :disabled in-use :title (and in-use (delete-confirmation media references))
                    (~icon :name :delete)))
                (button :type "button" :commandfor "media-preview" :command "close"
                        :class "btn btn-icon" :aria-label "Close" (~icon :name :close))))
            (div :class "flex max-h-[65vh] items-center justify-center bg-fg/5 p-4"
              (img :src (media-url media :absolute nil) :alt (media-alt media)
                   :class "max-h-[60vh] max-w-full object-contain"))
            (form :hx-post (save-alt :space space :id (media-id media))
                  :hx-target "#alt-saved" :hx-swap "innerHTML"
                  :class "flex items-center gap-2 border-t border-line px-4 py-3"
              (input :type "text" :name "alt" :value (media-alt media) :placeholder "alt text"
                     :class "input" :aria-label "alt text")
              (button :type "submit" :class "btn btn-icon" :aria-label "Save alt text" (~icon :name :check))
              ;; the flash would be behind the dialog, so the answer is shown here
              (span :id "alt-saved" :class "shrink-0 text-sm text-ok")))))))))

;;; --- The work ------------------------------------------------------------------
;;; Each returns (values MESSAGE KIND) for the flash.

(defun upload (space files)
  (handler-case
      (cond ((null files) (values "Choose at least one image." :error))
            (t (dolist (file files)
                 (store-upload space (first file) :filename (second file)))
               (values (format nil "Uploaded ~a file~:p." (length files)) :ok)))
    (api-error (e) (values (api-error-message e) :error))))

(defun delete-one (space id)
  (let ((media (find-media space id)))
    (handler-case
        (cond ((null media) (values "Media not found." :error))
              (t (remove-media media) (values "Media deleted." :ok)))
      (api-error (e) (values (api-error-message e) :error)))))

(defun delete-many (space ids)
  "One at a time: a file in use is refused, the rest still go."
  (if (null ids)
      (values "Nothing was selected." :error)
      (let ((done 0) (failed 0) (message nil))
        (dolist (id ids)
          (handler-case
              (let ((media (find-media space id)))
                (cond ((null media)
                       (incf failed)
                       (unless message (setf message "one was gone already")))
                      (t (remove-media media) (incf done))))
            ;; every condition, not only the store's own: a file that will not
            ;; leave the disk must not take the selection down with it
            (api-error (e)
              (incf failed)
              (unless message (setf message (api-error-message e))))
            (error (e)
              (incf failed)
              (unless message (setf message (princ-to-string e))))))
        (if (zerop failed)
            (values (format nil "Deleted ~a file~:p." done) :ok)
            (values (format nil "Deleted ~a of ~a; ~a could not be~@[: ~a~]" done (+ done failed) failed message)
                    :error)))))

;;; --- Actions ------------------------------------------------------------------

(defun action-space (params)
  (let ((space (param params "space")))
    (and space (find-space space) space)))

(defun answer (params space message kind &key close-preview)
  "#library at the search and page it was read at, with MESSAGE as the flash.
CLOSE-PREVIEW puts an empty, closed dialog in place of the open one."
  (let ((library (hsx (~library :space space :search (param params "q") :page (page-number params))))
        (flash (hsx (~flash-oob :message message :kind kind))))
    (if close-preview
        (hsx (<> library (~media-preview-dialog :oob t) flash))
        (hsx (<> library flash)))))

(defaction upload-media :post (params)
  (let ((space (action-space params)))
    (if space
        (multiple-value-bind (message kind) (upload space (uploaded-files params "file"))
          (answer params space message kind))
        (action-refusal "Space not found." 404))))

(defaction delete-media-action :post (params)
  (let ((space (action-space params)))
    (if space
        (multiple-value-bind (message kind) (delete-one space (or (param params "id") ""))
          (answer params space message kind :close-preview t))
        (action-refusal "Space not found." 404))))

(defaction delete-selected-media :post (params)
  (let ((space (action-space params)))
    (if space
        (multiple-value-bind (message kind) (delete-many space (form-values params "id"))
          (answer params space message kind))
        (action-refusal "Space not found." 404))))

(defaction preview-media :get (params)
  (let* ((space (action-space params))
         (media (and space (find-media space (or (param params "id") "")))))
    (if media
        (hsx (~media-preview-dialog :space space :media media :search (param params "q") :page (page-number params)
                                    :references (gethash (media-id media)
                                                         (media-reference-counts space (list (media-id media))) 0)))
        (action-refusal "Media not found." 404))))

(defaction save-alt :post (params)
  (let* ((space (action-space params))
         (media (and space (find-media space (or (param params "id") "")))))
    (cond ((null media) (action-refusal "Media not found." 404))
          (t (update-media space (media-id media) :alt (or (param params "alt") ""))
             (hsx (<> "Saved."))))))

;;; --- Page ---------------------------------------------------------------------

(defun @get (params)
  (with-owner
    (let ((space (let ((name (path-param params :space))) (and (find-space name) name))))
      (cond ((null space) (set-response-status 404) (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
            (t (set-title (format nil "Media · ~a · koya" space))
               (hsx (~layout :space space :crumbs (list (cons "Media" nil))
                      (~library :space space :search (param params "q") :page (page-number params))
                      (~media-preview-dialog))))))))
