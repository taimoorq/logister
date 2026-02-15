CREATE DATABASE IF NOT EXISTS logister;

CREATE TABLE IF NOT EXISTS logister.events_raw
(
  event_id UUID,
  project_id UInt64,
  api_key_id UInt64,
  occurred_at DateTime64(3, 'UTC'),
  received_at DateTime64(3, 'UTC') DEFAULT now64(3),

  event_type Enum8('error' = 1, 'metric' = 2),
  level LowCardinality(String),
  environment LowCardinality(String),
  service LowCardinality(String),
  release LowCardinality(String),

  fingerprint String,
  message String,
  exception_class LowCardinality(String),
  transaction_name String,

  tags Map(String, String),
  context_json String,

  ip IPv6 DEFAULT toIPv6('::'),
  user_agent String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (project_id, event_type, occurred_at, fingerprint, event_id)
TTL occurred_at + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS logister.events_1m
(
  bucket DateTime('UTC'),
  project_id UInt64,
  event_type Enum8('error' = 1, 'metric' = 2),
  level LowCardinality(String),
  count AggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(bucket)
ORDER BY (project_id, event_type, level, bucket);

CREATE MATERIALIZED VIEW IF NOT EXISTS logister.mv_events_1m
TO logister.events_1m
AS
SELECT
  toStartOfMinute(occurred_at) AS bucket,
  project_id,
  event_type,
  level,
  sumState(toUInt64(1)) AS count
FROM logister.events_raw
GROUP BY bucket, project_id, event_type, level;
