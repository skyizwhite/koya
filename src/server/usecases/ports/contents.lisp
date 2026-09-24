(defpackage #:koya-server/usecases/ports/contents
  (:use #:cl)
  (:export #:get-content
           #:find-content
           #:find-contents-by-ids
           #:find-object-content
           #:list-contents
           #:count-contents
           #:space-contents
           #:create-content
           #:save-draft
           #:publish-content
           #:unpublish-content
           #:discard-draft
           #:delete-content
           #:import-content
           #:ensure-draft-key
           #:unique-value-taken-p
           #:content-references
           #:list-revisions
           #:count-revisions
           #:find-revision
           #:content-history
           #:import-revision))
(in-package #:koya-server/usecases/ports/contents)

;;; Contents (domain/content) and the revision each write leaves
;;; (domain/revision). A write records its revision itself, naming whoever BY
;;; says. See ports/store for what a port is.

(declaim (ftype function get-content find-content find-contents-by-ids find-object-content
                list-contents count-contents space-contents
                create-content save-draft publish-content unpublish-content discard-draft
                delete-content import-content ensure-draft-key
                unique-value-taken-p content-references
                list-revisions count-revisions find-revision content-history import-revision))
