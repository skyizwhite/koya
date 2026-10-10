(defpackage #:koya-server/web/pages/s/<space>/media
  (:use #:cl #:hsx)
  (:import-from #:quri #:make-uri #:render-uri)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/lib/binds #:on-submit #:on-follow #:on-search #:on-pick)
  (:import-from #:koya-server/usecases/spaces #:find-space)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-filename #:media-size #:media-alt #:media-created-at)
  (:import-from #:koya-server/web/lib/presenters #:media-url)
  (:import-from #:koya-server/usecases/media
                #:remove-media #:store-uploads #:remove-each #:list-media #:count-media
                #:find-media #:update-media #:media-reference-counts #:media-references)
  (:import-from #:koya-server/web/lib/http
                #:path-param #:uploaded-files #:param #:form-list)
  (:import-from #:koya-server/domain/errors #:koya-error #:koya-error-message)
  (:import-from #:koya-server/web/lib/paging #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/web/lib/display #:short-time)
  (:import-from #:koya-server/web/lib/urls #:space-url)
  (:import-from #:koya-server/web/lib/document #:set-title)
  (:import-from #:koya-server/web/ui/layout #:~layout #:~missing)
  (:import-from #:koya-server/web/ui/elements #:~empty-state #:~pager #:~replace-url #:~referrers)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:~toast #:action-refusal)
  (:import-from #:koya-server/web/ui/media/grid #:~thumb #:dimensions #:human-size #:~upload-limit)
  (:export #:@get #:media-page-url
           #:browse-media #:upload-media #:delete-media-action #:delete-selected-media #:preview-media #:save-alt))
(in-package #:koya-server/web/pages/s/<space>/media)

(defparameter +library-size+ 24)

(defun media-page-url (space) (format nil "~a/media" (space-url space)))

(defun library-url (space &key search (page 1))
  (render-uri (make-uri :path (media-page-url space)
                        :query (append (and search (plusp (length search)) `(("q" . ,search)))
                                       (and (> page 1) `(("page" . ,page)))))))

(defparameter +bulk-form+ "media-bulk")

(defun delete-confirmation (media references)
  (if (plusp (or references 0))
      (format nil "~a is used by ~a content~:p and cannot be deleted until they stop using it. Remove it from them first."
              (media-filename media) references)
      (format nil "Delete ~a?" (media-filename media))))

(defcomp ~media-card (&key space media references search page)
  (let ((id (media-id media))
        (in-use (plusp (or references 0))))
    (hsx
     (li :class "relative"
       (input :type "checkbox" :name "id" :value id :form +bulk-form+ :data-bulk-item t
              :nm-bind "{ checked: () => _picked(this.value), onchange: () => _pick(this.value, this.checked) }"
              :class "absolute left-1 top-1 z-10 h-4 w-4 cursor-pointer"
              :aria-label (format nil "Select ~a" (media-filename media)))
       (button :type "button" :class "block w-full cursor-zoom-in"
               :nm-bind (on-follow (preview-media :space space :id id :q (or search "") :page page))
               :title (media-filename media)
               :aria-label (format nil "Preview ~a" (media-filename media))
         (~thumb :media media))
       (form :class "absolute right-1 top-1"
             :nm-bind (on-submit (delete-media-action :space space :q (or search "") :page page)
                                 :confirm (delete-confirmation media references))
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
     (div :id "library" :nm-data "...koya.bulk(this)"
       (form :nm-bind (on-pick (upload-media :space space :q q :page page))
             :class "mb-8 flex flex-wrap items-center gap-3 rounded-md border border-dashed border-line p-3 text-sm"
         (label :class "btn" (~icon :name :upload) "Upload"
           (input :type "file" :name "file" :accept "image/png,image/jpeg,image/gif,image/webp"
                  :multiple t :class "hidden"))
         (span :class "text-muted" "PNG, JPEG, GIF or WebP, several at once.")
         (~upload-limit))
       (if (null items)
           (hsx (~empty-state (if (plusp (length q)) "No file matches." "No media yet. Upload an image above.")))
           (hsx
            (<>
              (div :class "mb-4 flex flex-wrap items-center gap-3"
                (label :class "flex items-center gap-2 text-sm text-muted"
                  (input :type "checkbox" :form +bulk-form+
                         :nm-bind "{ checked: () => _all(), indeterminate: () => _partly(), onchange: () => _pickAll(this.checked) }")
                  "Select all on this page")
                (form :id +bulk-form+
                      :nm-bind (on-submit (delete-selected-media :space space :q q :page page)
                                          :data "{ id: _chosen }"
                                          :confirm "Delete the selected files? This cannot be undone.")
                  (div :hidden t :nm-bind "{ hidden: () => !_count() }" :class "flex flex-wrap items-center gap-2 text-sm"
                    (span :class "mr-1 text-muted" :nm-bind "{ textContent: () => `${_count()} selected` }" "0 selected")
                    (button :type "submit" :class "btn btn-danger" (~icon :name :delete) "Delete"))))
              (ul :class "grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6"
                (loop :for media :in items :collect
                  (hsx (~media-card :space space :media media :search search :page page
                                    :references (gethash (media-id media) references 0))))))))
       (~pager :page page :pages pages
               :href (lambda (n) (library-url space :search search :page n))
               :browse (lambda (n) (browse-media :space space :q q :page n)))))))

(defcomp ~media-count (&key space search)
  (hsx (span :id "media-count" :class "ml-3 text-base font-normal text-muted"
         (format nil "~a file~:p" (count-media space :search search)))))

(defcomp ~library-header (&key space search)
  (hsx
   (div :class "mb-6 flex flex-wrap items-center justify-between gap-4"
     (h1 :class "text-2xl font-bold" "Media" (~media-count :space space :search search))
     (form :method "get" :action (media-page-url space) :class "flex gap-2"
           :nm-data "...koya.search()" :nm-bind (on-search (browse-media :space space))
       (input :type "search" :name "q" :value (or search "") :placeholder "Search file names"
              :aria-label "Search" :class "input")))))

(defcomp ~alt-saved (&key message)
  (hsx (span :id "alt-saved" :class "shrink-0 text-sm text-ok" message)))

(defcomp ~media-preview-dialog (&key space media references search page)
  (let ((in-use (and media references t))
        (count (length references)))
    (hsx
     (dialog :id "media-preview" :closedby "any"
             :nm-bind (and media "{ oninit: () => this.showModal() }")
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
                (form :nm-bind (on-submit (delete-media-action :space space :q (or search "") :page page)
                                          :confirm (delete-confirmation media count))
                  (input :type "hidden" :name "id" :value (media-id media))
                  (button :type "submit" :class "btn btn-danger btn-icon" :aria-label "Delete"
                          :disabled in-use :title (and in-use (delete-confirmation media count))
                    (~icon :name :delete)))
                (button :type "button" :commandfor "media-preview" :command "close"
                        :class "btn btn-icon" :aria-label "Close" (~icon :name :close))))
            (div :class "flex max-h-[65vh] items-center justify-center bg-fg/5 p-4"
              (img :src (media-url media :absolute nil) :alt (media-alt media)
                   :class "max-h-[60vh] max-w-full object-contain"))
            (form :nm-bind (on-submit (save-alt :space space :id (media-id media)))
                  :class "flex items-center gap-2 border-t border-line px-4 py-3"
              (input :type "text" :name "alt" :value (media-alt media) :placeholder "alt text"
                     :class "input" :aria-label "alt text")
              (button :type "submit" :class "btn btn-icon" :aria-label "Save alt text" (~icon :name :check))
              (~alt-saved))
            (when references
              (hsx (div :class "border-t border-line px-4 py-3"
                     (~referrers :space space :heading "Used by" :references references)))))))))))

(defun upload (space files)
  (handler-case
      (cond ((null files) (values "Choose at least one image." :error))
            (t (values (format nil "Uploaded ~a file~:p." (length (store-uploads space files))) :ok)))
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

(defun action-space (params)
  (let ((space (param params "space")))
    (and space (find-space space) space)))

(defun answer (params space &key message kind close-preview)
  (let* ((search (param params "q"))
         (pages (last-page (count-media space :search search) +library-size+))
         (page (min (page-number params) pages)))
    (let ((library (hsx (<> (~library :space space :search search :page page)
                            (~replace-url :url (library-url space :search search :page page)))))
          (count (hsx (~media-count :space space :search search)))
          (toast (if message (hsx (~toast :message message :kind kind)) (hsx (<>)))))
      (if close-preview
          (hsx (<> library count (~media-preview-dialog) toast))
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
        (multiple-value-bind (message kind) (delete-many space (form-list params "id"))
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
                                    :references (media-references space (media-id media))))
        (action-refusal "Media not found." 404))))

(defaction save-alt :post (params)
  (let* ((space (action-space params))
         (media (and space (find-media space (or (param params "id") "")))))
    (cond ((null media) (action-refusal "Media not found." 404))
          (t (update-media space (media-id media) :alt (or (param params "alt") ""))
             (hsx (~alt-saved :message "Saved."))))))

(defun @get (params)
  (let ((space (let ((name (path-param params :space))) (and (find-space name) name))))
    (cond ((null space) (hsx (~missing :what "Space")))
          (t (set-title (format nil "Media · ~a · koya" space))
             (hsx (~layout :space space :crumbs (list (cons "Media" nil))
                    (~library-header :space space :search (param params "q"))
                    (~library :space space :search (param params "q") :page (page-number params))
                    (~media-preview-dialog)))))))
