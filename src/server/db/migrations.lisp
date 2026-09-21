(defpackage #:koya-server/db/migrations
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec
                #:fetch
                #:fetch-one
                #:col
                #:with-db-transaction)
  (:import-from #:koya/core/time
                #:now-iso)
  (:export #:migrate
           #:current-version))
(in-package #:koya-server/db/migrations)

;;; Forward-only migrations applied at startup. Each entry is (VERSION . STATEMENTS).

(defparameter *migrations*
  '((1
     "CREATE TABLE spaces (
        name TEXT PRIMARY KEY,
        webhooks TEXT NOT NULL DEFAULT '[]',
        webhook_secret TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL)"
     "CREATE TABLE models (
        space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        definition TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (space, name))"
     "CREATE TABLE contents (
        id TEXT PRIMARY KEY,
        space TEXT NOT NULL,
        model TEXT NOT NULL,
        status TEXT NOT NULL,
        published TEXT,
        draft TEXT,
        draft_key TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        published_at TEXT,
        revised_at TEXT,
        FOREIGN KEY (space, model) REFERENCES models(space, name) ON DELETE CASCADE)"
     "CREATE INDEX contents_by_model ON contents (space, model, status, published_at)"
     "CREATE TABLE api_keys (
        id TEXT PRIMARY KEY,
        space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
        key_hash TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL)"
     "CREATE TABLE media (
        id TEXT PRIMARY KEY,
        space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
        filename TEXT NOT NULL,
        mime TEXT NOT NULL,
        size INTEGER NOT NULL,
        width INTEGER,
        height INTEGER,
        alt TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL)")
    (2
     "CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL)")
    (3
     "CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        expires_at TEXT NOT NULL)")
    (4
     "CREATE TABLE management_keys (
        id TEXT PRIMARY KEY,
        key_hash TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL)")
    (5
     "CREATE TABLE webhook_deliveries (
        id TEXT PRIMARY KEY,
        space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
        label TEXT NOT NULL DEFAULT '',
        url TEXT NOT NULL,
        model TEXT NOT NULL DEFAULT '',
        event TEXT NOT NULL,
        content_id TEXT NOT NULL DEFAULT '',
        ok INTEGER NOT NULL,
        status INTEGER,
        response TEXT NOT NULL DEFAULT '',
        error TEXT NOT NULL DEFAULT '',
        duration_ms INTEGER,
        created_at TEXT NOT NULL)"
     "CREATE INDEX webhook_deliveries_by_space ON webhook_deliveries (space, id DESC)")
    (6
     ;; management keys belong to one space; the old instance-wide ones cannot be
     ;; assigned to one, so they are dropped and have to be made again
     "DROP TABLE management_keys"
     "CREATE TABLE management_keys (
        id TEXT PRIMARY KEY,
        space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
        key_hash TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL)")))

(defun ensure-version-table ()
  (exec "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)"))

(defun current-version ()
  (ensure-version-table)
  (or (col (fetch-one "SELECT MAX(version) AS version FROM schema_version") "version") 0))

(defun migrate ()
  "Apply all pending migrations. Returns the list of versions applied."
  (let ((applied '()))
    (loop :for (version . statements) :in *migrations*
          :when (> version (current-version))
            :do (with-db-transaction
                  (dolist (sql statements) (exec sql))
                  (exec "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)" version (now-iso)))
                (push version applied))
    (nreverse applied)))
