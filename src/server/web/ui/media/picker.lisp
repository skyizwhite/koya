(defpackage #:koya-server/web/ui/media/picker
  (:use #:cl #:hsx)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/usecases/spaces #:find-space)
  (:import-from #:koya-server/usecases/media #:list-media #:count-media)
  (:import-from #:koya-server/web/lib/http #:param #:set-response-status)
  (:import-from #:koya-server/web/lib/paging #:page-number #:last-page #:page-offset)
  (:import-from #:koya-server/web/ui/elements #:~search-form)
  (:import-from #:koya-server/web/ui/media/grid #:~media-grid #:~pick-cards)
  (:import-from #:koya-server/web/ui/media/upload #:~upload-form)
  (:import-from #:koya-server/web/ui/picker #:~picker-dialog)
  (:export #:media-picker
           #:media-picker-search
           #:media-picker-more
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

(defcomp ~picker-body (&key space search)
  (hsx
   (div :id "media-picker-body" :class "space-y-4"
     (~search-form :id "media-picker-search-form" :url (media-picker-search :space space) :class "flex gap-2"
       (input :type "search" :name "q" :value (or search "") :placeholder "Search file names" :class "input" :aria-label "Search"))
     (~upload-form :space space :redraw (media-picker-search :space space) :search "media-picker-search-form"
                   :hint "PNG, JPEG, GIF or WebP. Uploaded files are added to the library.")
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

(defcomp ~media-picker-dialog (&key space)
  (hsx (~picker-dialog :id "media-picker" :class "max-w-3xl" :title "Media" :factory "mediaPicker"
                       :url (media-picker :space space) :add-label "Add")))
