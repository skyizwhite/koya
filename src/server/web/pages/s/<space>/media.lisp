(defpackage #:koya-server/web/pages/s/<space>/media
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:jingle #:set-response-status #:set-response-header)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:find-space)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-filename #:media-size #:media-alt #:media-created-at)
  (:import-from #:koya-server/web/presenters #:media-url)
  (:import-from #:koya-server/usecases/media/library
                #:remove-media #:store-uploads #:remove-each #:list-media #:count-media
                #:find-media #:update-media #:media-reference-counts)
  (:import-from #:koya-server/web/http
                #:path-param #:uploaded-files #:param #:form-values)
  (:import-from #:koya-server/domain/errors #:koya-error #:koya-error-message)
  (:import-from #:koya-server/web/paging #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/web/display #:short-time)
  (:import-from #:koya-server/web/urls #:space-url)
  (:import-from #:koya-server/web/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout)
  (:import-from #:koya-server/web/ui/elements #:~empty-state)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:~toast-oob #:action-refusal)
  (:import-from #:koya-server/web/ui/media/grid #:~thumb #:dimensions #:human-size)
  (:export #:@get #:media-page-url
           #:browse-media #:upload-media #:delete-media-action #:delete-selected-media #:preview-media #:save-alt))
(in-package #:koya-server/web/pages/s/<space>/media)

;;; The media library. Searching, paging and what is done to the files are all
;;; actions answered in place: #library -- the upload row, the selection, the grid
;;; and the pager -- is drawn again, with the count out of band, and the URL is
;;; replaced with the search and page, so a reload or a link comes back to them.
;;; The preview dialog is drawn by the server for the file it opens.

(defparameter +library-size+ 24
  "Files per page: four rows of the six columns a wide screen shows.")

(defun media-page-url (space) (format nil "~a/media" (space-url space)))

(defun library-url (space &key search (page 1))
  "The library as it is being read: the search and the page, when they are not the first."
  (render-uri (make-uri :path (media-page-url space)
                        :query (append (and search (plusp (length search)) `(("q" . ,search)))
                                       (and (> page 1) `(("page" . ,page)))))))

(defparameter +bulk-form+ "media-bulk"
  "The selection form's id: the boxes are on the cards and join it by their form
attribute, because the card already holds a form and forms do not nest.")

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
         (pages (last-page total +library-size+))
         (page (min page pages))
         (items (list-media space :search search :limit +library-size+ :offset (page-offset page +library-size+)))
         (references (media-reference-counts space (mapcar #'media-id items)))
         (q (or search "")))
    (hsx
     (div :id "library"
       ;; the files go up as soon as they are chosen, as in the picker
       ;; (ui/media/picker); alt text is written afterwards, in the preview
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
         (flet ((page-link (n)
                  (hsx (a :href (library-url space :search search :page n)
                          :hx-get (browse-media :space space :q q :page n) :hx-target "#library" :hx-swap "outerHTML"
                          :class "btn"
                          (if (< n page)
                              (hsx (<> (~icon :name :prev) "Previous"))
                              (hsx (<> "Next" (~icon :name :next))))))))
           (hsx (nav :class "mt-8 flex items-center justify-center gap-3 text-sm"
                  (when (> page 1) (page-link (1- page)))
                  (span :class "text-muted" (format nil "Page ~a of ~a" page pages))
                  (when (< page pages) (page-link (1+ page)))))))))))

(defcomp ~media-count (&key space search oob)
  (hsx (span :id "media-count" :class "ml-3 text-base font-normal text-muted" :hx-swap-oob (and oob "true")
         (format nil "~a file~:p" (count-media space :search search)))))

(defcomp ~library-header (&key space search)
  "The title, the count and the search box, outside #library: typing draws the
library again, and the box keeps its focus."
  (hsx
   (div :class "mb-6 flex flex-wrap items-center justify-between gap-4"
     (h1 :class "text-2xl font-bold" "Media" (~media-count :space space :search search))
     (form :method "get" :action (media-page-url space) :class "flex gap-2"
           :hx-get (browse-media :space space) :hx-target "#library" :hx-swap "outerHTML"
           :hx-trigger "input changed delay:300ms from:'find input', submit"
       (input :type "search" :name "q" :value (or search "") :placeholder "Search file names"
              :aria-label "Search" :class "input")))))

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
              ;; the toast would be behind the dialog, so the answer is shown here
              (span :id "alt-saved" :class "shrink-0 text-sm text-ok")))))))))

;;; --- The work ------------------------------------------------------------------
;;; Each returns (values MESSAGE KIND) for the toast.

(defun upload (space files)
  (handler-case
      (cond ((null files) (values "Choose at least one image." :error))
            (t (values (format nil "Uploaded ~a file~:p." (store-uploads space files)) :ok)))
    (koya-error (e) (values (koya-error-message e) :error))))

(defun delete-one (space id)
  (let ((media (find-media space id)))
    (handler-case
        (cond ((null media) (values "Media not found." :error))
              (t (remove-media media) (values "Media deleted." :ok)))
      (koya-error (e) (values (koya-error-message e) :error)))))

(defun delete-many (space ids)
  (if (null ids)
      (values "Nothing was selected." :error)
      (multiple-value-bind (done failed message) (remove-each space ids)
        (if (zerop failed)
            (values (format nil "Deleted ~a file~:p." done) :ok)
            (values (format nil "Deleted ~a of ~a; ~a could not be~@[: ~a~]" done (+ done failed) failed message)
                    :error)))))

;;; --- Actions ------------------------------------------------------------------

(defun action-space (params)
  (let ((space (param params "space")))
    (and space (find-space space) space)))

(defun answer (params space &key message kind close-preview)
  "#library and the count at the search and page it was read at (the last page,
when that one has emptied), the URL it is now read at, and MESSAGE as the toast.
CLOSE-PREVIEW puts an empty, closed dialog in place of the open one."
  (let* ((search (param params "q"))
         (pages (last-page (count-media space :search search) +library-size+))
         (page (min (page-number params) pages)))
    (set-response-header :hx-replace-url (library-url space :search search :page page))
    (let ((library (hsx (~library :space space :search search :page page)))
          (count (hsx (~media-count :space space :search search :oob t)))
          (toast (if message (hsx (~toast-oob :message message :kind kind)) (hsx (<>)))))
      (if close-preview
          (hsx (<> library count (~media-preview-dialog :oob t) toast))
          (hsx (<> library count toast))))))

(defaction upload-media :post (params)
  (let ((space (action-space params)))
    (if space
        (multiple-value-bind (message kind) (upload space (uploaded-files params "file"))
          (answer params space :message message :kind kind))
        (action-refusal "Space not found." 404))))

(defaction delete-media-action :post (params)
  (let ((space (action-space params)))
    (if space
        (multiple-value-bind (message kind) (delete-one space (or (param params "id") ""))
          (answer params space :message message :kind kind :close-preview t))
        (action-refusal "Space not found." 404))))

(defaction delete-selected-media :post (params)
  (let ((space (action-space params)))
    (if space
        (multiple-value-bind (message kind) (delete-many space (form-values params "id"))
          (answer params space :message message :kind kind))
        (action-refusal "Space not found." 404))))

(defaction browse-media :get (params)
  (let ((space (action-space params)))
    (if space (answer params space) (action-refusal "Space not found." 404))))

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
  (let ((space (let ((name (path-param params :space))) (and (find-space name) name))))
    (cond ((null space) (set-response-status 404) (hsx (~layout (h1 :class "text-xl font-bold" "Space not found"))))
          (t (set-title (format nil "Media · ~a · koya" space))
             (hsx (~layout :space space :crumbs (list (cons "Media" nil))
                    (~library-header :space space :search (param params "q"))
                    (~library :space space :search (param params "q") :page (page-number params))
                    (~media-preview-dialog)))))))
