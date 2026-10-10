(defpackage #:koya-server/infra/db/migrations
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection
                #:exec #:fetch #:fetch-one #:col #:with-db-transaction)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-core/json #:parse-json #:to-json #:jget)
  (:import-from #:koya-server/infra/db/contents #:text-column #:refresh-slugs)
  (:export #:migrate
           #:current-version))
(in-package #:koya-server/infra/db/migrations)

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
     "DROP TABLE management_keys"
     "CREATE TABLE management_keys (
        id TEXT PRIMARY KEY,
        space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
        key_hash TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL)")
    (7
     "CREATE TABLE schema_deploys (
        id TEXT PRIMARY KEY,
        space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
        changes TEXT NOT NULL,
        change_count INTEGER NOT NULL,
        destructive INTEGER NOT NULL,
        deployed_by TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL)"
     "CREATE INDEX schema_deploys_by_space ON schema_deploys (space, id DESC)")
    (8
     "ALTER TABLE api_keys RENAME TO delivery_keys")
    (9
     "CREATE TABLE content_revisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content_id TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
        event TEXT NOT NULL,
        data TEXT NOT NULL,
        written_by TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL)"
     "CREATE INDEX content_revisions_by_content ON content_revisions (content_id, id DESC)"
     "INSERT INTO content_revisions (content_id, event, data, created_at)
        SELECT id, 'publish', published, COALESCE(revised_at, updated_at) FROM contents
         WHERE published IS NOT NULL ORDER BY created_at"
     "INSERT INTO content_revisions (content_id, event, data, created_at)
        SELECT id, 'draft', draft, updated_at FROM contents
         WHERE draft IS NOT NULL ORDER BY created_at")
    (10
     "UPDATE models SET definition = json_remove(definition, '$.previewUrl')
       WHERE json_type(definition, '$.previewUrl') IS NOT NULL
         AND NOT (json_type(definition, '$.previewUrl') = 'text'
                  AND (json_extract(definition, '$.previewUrl') LIKE 'http://_%'
                       OR json_extract(definition, '$.previewUrl') LIKE 'https://_%'))"
     "UPDATE models SET definition = json_remove(definition, '$.publicUrl')
       WHERE json_type(definition, '$.publicUrl') IS NOT NULL
         AND NOT (json_type(definition, '$.publicUrl') = 'text'
                  AND (json_extract(definition, '$.publicUrl') LIKE 'http://_%'
                       OR json_extract(definition, '$.publicUrl') LIKE 'https://_%'))")
    (11
     "UPDATE spaces SET webhooks =
        (SELECT json_group_array(json(hook.value)) FROM json_each(spaces.webhooks) AS hook
          WHERE json_type(hook.value, '$.url') = 'text'
            AND (json_extract(hook.value, '$.url') LIKE 'http://_%'
                 OR json_extract(hook.value, '$.url') LIKE 'https://_%'))
       WHERE EXISTS (SELECT 1 FROM json_each(spaces.webhooks) AS hook
                      WHERE NOT (json_type(hook.value, '$.url') = 'text'
                                 AND (json_extract(hook.value, '$.url') LIKE 'http://_%'
                                      OR json_extract(hook.value, '$.url') LIKE 'https://_%')))")
    (12
     "UPDATE contents SET
        published = (SELECT json_group_object(e.key, json(contents.published -> e.fullkey))
                       FROM json_each(contents.published) e
                      WHERE e.key IN (SELECT json_extract(f.value, '$.name')
                                        FROM models m, json_each(m.definition, '$.fields') f
                                       WHERE m.space = contents.space AND m.name = contents.model))
       WHERE published IS NOT NULL"
     "UPDATE contents SET
        draft = (SELECT json_group_object(e.key, json(contents.draft -> e.fullkey))
                   FROM json_each(contents.draft) e
                  WHERE e.key IN (SELECT json_extract(f.value, '$.name')
                                    FROM models m, json_each(m.definition, '$.fields') f
                                   WHERE m.space = contents.space AND m.name = contents.model))
       WHERE draft IS NOT NULL"
     "UPDATE content_revisions SET
        data = (SELECT json_group_object(e.key, json(content_revisions.data -> e.fullkey))
                  FROM json_each(content_revisions.data) e
                 WHERE e.key IN (SELECT json_extract(f.value, '$.name')
                                   FROM contents c, models m, json_each(m.definition, '$.fields') f
                                  WHERE c.id = content_revisions.content_id
                                    AND m.space = c.space AND m.name = c.model))")
    (13
     :foreign-keys-off
     "CREATE TABLE contents_by_space (
        id TEXT NOT NULL,
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
        PRIMARY KEY (space, id),
        FOREIGN KEY (space, model) REFERENCES models(space, name) ON DELETE CASCADE)"
     "INSERT INTO contents_by_space (id, space, model, status, published, draft, draft_key,
                                     created_at, updated_at, published_at, revised_at)
        SELECT id, space, model, status, published, draft, draft_key,
               created_at, updated_at, published_at, revised_at FROM contents"
     "CREATE TABLE content_revisions_by_space (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        space TEXT NOT NULL,
        content_id TEXT NOT NULL,
        event TEXT NOT NULL,
        data TEXT NOT NULL,
        written_by TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (space, content_id) REFERENCES contents(space, id) ON DELETE CASCADE)"
     "INSERT INTO content_revisions_by_space (id, space, content_id, event, data, written_by, created_at)
        SELECT r.id, c.space, r.content_id, r.event, r.data, r.written_by, r.created_at
          FROM content_revisions r JOIN contents c ON c.id = r.content_id"
     "DROP TABLE content_revisions"
     "DROP TABLE contents"
     "ALTER TABLE contents_by_space RENAME TO contents"
     "ALTER TABLE content_revisions_by_space RENAME TO content_revisions"
     "CREATE INDEX contents_by_model ON contents (space, model, status, published_at)"
     "CREATE INDEX content_revisions_by_content ON content_revisions (space, content_id, id DESC)")
    (14
     "ALTER TABLE contents ADD COLUMN published_text TEXT"
     "ALTER TABLE contents ADD COLUMN draft_text TEXT"
     fill-content-texts)
    (15
     "ALTER TABLE spaces ADD COLUMN custom_fields TEXT NOT NULL DEFAULT '[]'")
    (16
     forget-slug-options
     "ALTER TABLE contents ADD COLUMN published_slug TEXT"
     "ALTER TABLE contents ADD COLUMN draft_slug TEXT"
     "CREATE INDEX contents_by_published_slug ON contents (space, model, published_slug)"
     "CREATE INDEX contents_by_draft_slug ON contents (space, model, draft_slug)"
     refresh-slugs)))

(defun forget-slug-options ()
  (dolist (row (fetch "SELECT space, name, definition FROM models"))
    (let ((definition (parse-json (col row "definition")))
          (changed nil))
      (loop :for field :across (or (jget definition "fields") #())
            :when (equal (jget field "type") "slug")
              :do (let ((from (remhash "from" field))
                        (unique (remhash "unique" field)))
                    (when (or from unique) (setf changed t))))
      (when changed
        (exec "UPDATE models SET definition = ? WHERE space = ? AND name = ?"
              (to-json definition) (col row "space") (col row "name"))))))

(defun fill-content-texts ()
  (flet ((text (json) (and json (text-column (parse-json json)))))
    (dolist (row (fetch "SELECT rowid AS r, published, draft FROM contents"))
      (exec "UPDATE contents SET published_text = ?, draft_text = ? WHERE rowid = ?"
            (text (col row "published")) (text (col row "draft")) (col row "r")))))

(defun ensure-version-table ()
  (exec "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)"))

(defun current-version ()
  (ensure-version-table)
  (or (col (fetch-one "SELECT MAX(version) AS version FROM schema_version") "version") 0))

(defun apply-migration (version statements &key check-keys)
  (with-db-transaction
    (dolist (step statements)
      (if (stringp step) (exec step) (funcall step)))
    (when (and check-keys (fetch "PRAGMA foreign_key_check"))
      (error "Migration ~a leaves rows whose foreign keys point nowhere" version))
    (exec "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)" version (now-iso))))

(defun migrate ()
  (let ((applied '()))
    (loop :for (version . statements) :in *migrations*
          :for keys-off := (eq (first statements) :foreign-keys-off)
          :when (> version (current-version))
            :do (if keys-off
                    (progn
                      (exec "PRAGMA foreign_keys = OFF")
                      (unwind-protect (apply-migration version (rest statements) :check-keys t)
                        (exec "PRAGMA foreign_keys = ON")))
                    (apply-migration version statements))
                (push version applied))
    (nreverse applied)))
