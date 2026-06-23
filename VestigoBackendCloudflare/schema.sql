CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  apns_token TEXT NOT NULL,
  environment TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id TEXT PRIMARY KEY,
  notifications_enabled INTEGER NOT NULL,
  enabled_kinds_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tracked_items (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  tmdb_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  release_date TEXT,
  reason TEXT NOT NULL,
  last_checked_at TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(user_id, tmdb_id, kind, reason)
);

CREATE TABLE IF NOT EXISTS notification_candidates (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  tracked_item_id TEXT NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  sent_at TEXT,
  UNIQUE(user_id, tracked_item_id, type)
);

CREATE TABLE IF NOT EXISTS provider_snapshots (
  tracked_item_id TEXT PRIMARY KEY,
  provider_hash TEXT NOT NULL,
  providers_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notification_snapshots (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  snapshot_type TEXT NOT NULL,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
