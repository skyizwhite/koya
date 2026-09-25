(defpackage #:koya-server/usecases/ports/spaces
  (:use #:cl)
  (:export #:list-spaces
           #:find-space
           #:insert-space
           #:delete-space
           #:load-schema
           #:save-schema
           #:find-model
           #:space-webhooks
           #:space-webhook-secret
           #:rotate-webhook-secret
           #:set-webhook-secret
           #:list-deploys
           #:count-deploys
           #:+deploys-kept+))
(in-package #:koya-server/usecases/ports/spaces)

;;; Spaces, the schema deployed to each, and the log of deploys.

(defgeneric list-spaces ()
  (:documentation "Every space as a plist (:name :models n), in display order."))

(defgeneric find-space (name)
  (:documentation "NAME when there is a space of that name, NIL otherwise: a missing space, told
apart from an empty one."))

(defgeneric insert-space (name)
  (:documentation "Store a new space named NAME, last in display order, with a fresh webhook
secret. Returns NAME."))

(defgeneric delete-space (name)
  (:documentation "Delete a space with everything in it: models, contents, media rows, keys, the
webhook log and the deploy log. The media files themselves are removed by the caller."))

(defgeneric load-schema (space-name)
  (:documentation "The schema of SPACE-NAME -- its webhooks and models -- or NIL when no such space."))

(defgeneric save-schema (space-name schema changes &key by)
  (:documentation "Store SCHEMA as the schema of SPACE-NAME, and log CHANGES as a deploy by BY,
in one transaction. CHANGES is what the caller found between the stored schema
and SCHEMA (core/diff); the renames in it are carried through to the stored
content, and a model that is no longer there is deleted with its contents.
Nothing is decided here: the caller checked SCHEMA and chose to apply it."))

(defgeneric find-model (space-name model-name))

(defgeneric space-webhooks (name)
  (:documentation "The webhooks every model of the space fires. Read on its own, without the
models, because every content change needs them."))

(defgeneric space-webhook-secret (space-name)
  (:documentation "The secret sent as X-KOYA-WEBHOOK-KEY with every webhook of SPACE-NAME."))

(defgeneric rotate-webhook-secret (space-name))

(defgeneric set-webhook-secret (space-name secret)
  (:documentation "Give SPACE-NAME the secret it had elsewhere: an imported space keeps the one
its site already checks."))

(defgeneric list-deploys (space &key limit offset)
  (:documentation "Newest first, to the millisecond a ULID carries."))

(defgeneric count-deploys (space))

(defparameter +deploys-kept+ 100
  "Deploys kept per space; older ones are dropped as new ones arrive.")
