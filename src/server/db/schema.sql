-- koya database schema, version 7.
--
-- Generated from src/server/db/migrations.lisp; do not edit by hand.
-- Regenerate it from the REPL with (koya-server:write-schema-snapshot).

CREATE TABLE api_keys (
  id TEXT PRIMARY KEY,
  space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
  key_hash TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL);
CREATE TABLE contents (
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
  FOREIGN KEY (space, model) REFERENCES models(space, name) ON DELETE CASCADE);
CREATE INDEX contents_by_model ON contents (space, model, status, published_at);
CREATE TABLE management_keys (
  id TEXT PRIMARY KEY,
  space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
  key_hash TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL);
CREATE TABLE media (
  id TEXT PRIMARY KEY,
  space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
  filename TEXT NOT NULL,
  mime TEXT NOT NULL,
  size INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  alt TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL);
CREATE TABLE models (
  space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  definition TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (space, name));
CREATE TABLE schema_deploys (
  id TEXT PRIMARY KEY,
  space TEXT NOT NULL REFERENCES spaces(name) ON DELETE CASCADE,
  changes TEXT NOT NULL,
  change_count INTEGER NOT NULL,
  destructive INTEGER NOT NULL,
  deployed_by TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL);
CREATE INDEX schema_deploys_by_space ON schema_deploys (space, id DESC);
CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  expires_at TEXT NOT NULL);
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL);
CREATE TABLE spaces (
  name TEXT PRIMARY KEY,
  webhooks TEXT NOT NULL DEFAULT '[]',
  webhook_secret TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL);
CREATE TABLE webhook_deliveries (
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
  created_at TEXT NOT NULL);
CREATE INDEX webhook_deliveries_by_space ON webhook_deliveries (space, id DESC);
