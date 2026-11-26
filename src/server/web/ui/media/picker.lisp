(defpackage #:koya-server/web/ui/media/picker
  (:use #:cl #:hsx)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/web/lib/binds #:upload-picked)
  (:import-from #:koya-server/usecases/spaces #:find-space)
  (:import-from #:koya-server/usecases/media #:store-uploads #:list-media #:count-media)
  (:import-from #:koya-server/web/lib/http #:uploaded-files #:param #:set-response-status)
  (:import-from #:koya-server/domain/errors #:koya-error #:koya-error-message)
  (:import-from #:koya-server/web/lib/paging #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/elements #:~search-form)
  (:import-from #:koya-server/web/ui/media/grid #:~media-grid #:~pick-cards #:~upload-limit)
  (:import-from #:koya-server/web/ui/picker #:~picker-dialog)
  (:export #:media-picker
           #:media-picker-search
           #:media-picker-more
           #:media-picker-upload
           #:~media-picker-dialog))
(in-package #:koya-server/web/ui/media/picker)

(defparameter +picker-size+ 12)

(defun picker-items (space search page)
  (let ((items (list-media space :search search :limit +picker-size+ :offset (page-offset page +picker-size+))))
    (values items
            (and (< page (last-page (count-media space :search search) +picker-size+))
                 (media-picker-more :space space :q (or search "") :page (1+ page))))))

(defcomp ~picker-grid (&key space search)
  (multiple-value-bind (items more) (picker-items space search 1)
    (hsx (div :id "media-picker-grid" (~media-grid :items items :more more)))))

(defcomp ~picker-body (&key space search error)
  (hsx
   (div :id "media-picker-body" :class "space-y-4"
     (~search-form :url (media-picker-search :space space) :class "flex gap-2"
       (input :type "search" :name "q" :value (or search "") :placeholder "Search file names" :class "input" :aria-label "Search"))
     (form :n-on-change (upload-picked (media-picker-upload :space space))
           :class "flex flex-wrap items-center gap-3 rounded-md border border-dashed border-line p-3 text-sm"
       (label :class "btn" (~icon :name :upload) "Upload"
         (input :type "file" :name "file" :accept "image/png,image/jpeg,image/gif,image/webp" :multiple t :class "hidden"))
       (span :class "text-muted" "PNG, JPEG, GIF or WebP. Uploaded files are added to the library.")
       (~upload-limit)
       (when error (hsx (span :class "text-danger" error))))
     (~picker-grid :space space :search search))))

(defun forbidden (message)
  (set-response-status 403)
  (hsx (div :id "media-picker-body" :class "text-sm text-danger" message)))

(defun picker-space (params)
  (let ((space (param params "space")))
    (and space (find-space space) space)))

(defaction media-picker :get (params)
  (cond ((null (picker-space params)) (forbidden "Unknown space."))
        (t (hsx (~picker-body :space (picker-space params) :search (param params "q"))))))

(defaction media-picker-search :get (params)
  (cond ((null (picker-space params)) (forbidden "Unknown space."))
        (t (hsx (~picker-grid :space (picker-space params) :search (param params "q"))))))

(defaction media-picker-more :get (params)
  (let ((space (picker-space params)))
    (if space
        (multiple-value-bind (items more) (picker-items space (param params "q") (page-number params))
          (let ((asked (media-picker-more :space space :q (or (param params "q") "") :page (page-number params))))
            (hsx (<> (ul :id asked :n-swap "before" (~pick-cards :items items :more more))
                     (li :id asked :hidden t)))))
        (forbidden "Unknown space."))))

(defaction media-picker-upload :post (params)
  (cond ((null (picker-space params)) (forbidden "Unknown space."))
        (t (let ((space (picker-space params))
                 (files (uploaded-files params "file")))
             (handler-case
                 (progn (store-uploads space files)
                        (hsx (~picker-body :space space)))
               (koya-error (e)
                 (hsx (~picker-body :space space :error (koya-error-message e)))))))))

(defcomp ~media-picker-dialog (&key space)
  (hsx (~picker-dialog :id "media-picker" :class "max-w-3xl" :title "Media" :factory "mediaPicker"
                       :url (media-picker :space space) :add-label "Add")))
