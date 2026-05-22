CREATE DATABASE IF NOT EXISTS logister;

CREATE TABLE IF NOT EXISTS logister.events_raw
(
  event_id UUID,
  project_id UInt64,
  api_key_id UInt64,
  occurred_at DateTime64(3, 'UTC'),
  received_at DateTime64(3, 'UTC') DEFAULT now64(3),

  event_type Enum8('error' = 1, 'metric' = 2, 'transaction' = 3, 'log' = 4, 'check_in' = 5),
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
TTL toDateTime(occurred_at) + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS logister.spans_raw
(
  span_id UUID,
  project_id UInt64,
  api_key_id UInt64,
  trace_id String,
  external_span_id String,
  parent_span_id String,
  name String,
  kind LowCardinality(String),
  status LowCardinality(String),
  duration_ms Float64,
  started_at DateTime64(3, 'UTC'),
  ended_at Nullable(DateTime64(3, 'UTC')),
  received_at DateTime64(3, 'UTC') DEFAULT now64(3),

  environment LowCardinality(String),
  service LowCardinality(String),
  release LowCardinality(String),
  route String,
  request_id String,

  tags Map(String, String),
  context_json String,

  ip IPv6 DEFAULT toIPv6('::'),
  user_agent String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(started_at)
ORDER BY (project_id, kind, started_at, trace_id, external_span_id)
TTL toDateTime(started_at) + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS logister.request_spans_1m
(
  bucket DateTime('UTC'),
  project_id UInt64,
  environment LowCardinality(String),
  route String,
  count AggregateFunction(sum, UInt64),
  duration_avg AggregateFunction(avg, Float64),
  duration_p95 AggregateFunction(quantileTDigest(0.95), Float64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(bucket)
ORDER BY (project_id, environment, route, bucket);

CREATE MATERIALIZED VIEW IF NOT EXISTS logister.mv_request_spans_1m
TO logister.request_spans_1m
AS
SELECT
  toStartOfMinute(started_at) AS bucket,
  project_id,
  environment,
  route,
  sumState(toUInt64(1)) AS count,
  avgState(duration_ms) AS duration_avg,
  quantileTDigestState(0.95)(duration_ms) AS duration_p95
FROM logister.spans_raw
WHERE kind IN ('server', 'browser') AND parent_span_id = ''
GROUP BY bucket, project_id, environment, route;

CREATE TABLE IF NOT EXISTS logister.events_1m
(
  bucket DateTime('UTC'),
  project_id UInt64,
  event_type Enum8('error' = 1, 'metric' = 2, 'transaction' = 3, 'log' = 4, 'check_in' = 5),
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
