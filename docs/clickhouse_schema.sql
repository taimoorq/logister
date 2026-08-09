-- Logister ClickHouse analytical schema, version 2.
--
-- events_raw and spans_raw are append/replay tables. A deterministic projector may
-- write the same logical record more than once after an ambiguous acknowledgement.
-- Product queries MUST use event_facts_v2/span_facts_v2 (or a view derived from
-- them), which select one version per project/telemetry UUID. This makes counts,
-- averages, and percentile inputs replay-correct independently of ClickHouse's
-- bounded insert_deduplication_token window.

CREATE DATABASE IF NOT EXISTS logister;

CREATE TABLE IF NOT EXISTS logister.events_raw
(
  event_id UUID,
  project_id UInt64,
  api_key_id UInt64,
  projection_version UInt64 DEFAULT 1,
  identity_checksum UInt128,
  occurred_at DateTime64(3, 'UTC'),
  received_at DateTime64(3, 'UTC'),

  event_type Enum8('error' = 1, 'metric' = 2, 'transaction' = 3, 'log' = 4, 'check_in' = 5),
  level LowCardinality(String),
  environment LowCardinality(String),
  service LowCardinality(String),
  release LowCardinality(String),

  fingerprint String,
  message String,
  exception_class LowCardinality(String),
  transaction_name String,
  trace_id String DEFAULT '',
  request_id String DEFAULT '',

  metric_name String DEFAULT '',
  metric_value Nullable(Float64),
  metric_unit LowCardinality(String) DEFAULT '',
  duration_ms Nullable(Float64),
  transaction_status LowCardinality(String) DEFAULT '',

  log_severity LowCardinality(String) DEFAULT '',
  error_fingerprint String DEFAULT '',
  check_in_slug String DEFAULT '',
  check_in_status LowCardinality(String) DEFAULT '',
  check_in_expected_interval_seconds Nullable(UInt32),

  tags Map(String, String),
  context_json String,
  ip IPv6 DEFAULT toIPv6('::'),
  user_agent String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (project_id, toDate(occurred_at), event_type, occurred_at, event_id)
TTL toDateTime(occurred_at) + INTERVAL 120 DAY DELETE
SETTINGS
  index_granularity = 8192,
  non_replicated_deduplication_window = 10000;

-- Additive evolution for installations that created events_raw from schema v1.
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS projection_version UInt64 DEFAULT 1;
-- Existing rows receive zero and must be replayed from the ledger/backfill. We do
-- not reinterpret UUID storage bytes because that is not the canonical big-endian
-- integer used by the PostgreSQL watermark checksum.
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS identity_checksum UInt128 DEFAULT 0;
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS trace_id String DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS request_id String DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS metric_name String DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS metric_value Nullable(Float64);
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS metric_unit LowCardinality(String) DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS duration_ms Nullable(Float64);
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS transaction_status LowCardinality(String) DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS log_severity LowCardinality(String) DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS error_fingerprint String DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS check_in_slug String DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS check_in_status LowCardinality(String) DEFAULT '';
ALTER TABLE logister.events_raw ADD COLUMN IF NOT EXISTS check_in_expected_interval_seconds Nullable(UInt32);
ALTER TABLE logister.events_raw MODIFY TTL toDateTime(occurred_at) + INTERVAL 120 DAY DELETE;

CREATE TABLE IF NOT EXISTS logister.spans_raw
(
  span_id UUID,
  project_id UInt64,
  api_key_id UInt64,
  projection_version UInt64 DEFAULT 1,
  identity_checksum UInt128,
  trace_id String,
  external_span_id String,
  parent_span_id String,
  name String,
  kind LowCardinality(String),
  status LowCardinality(String),
  duration_ms Float64,
  started_at DateTime64(3, 'UTC'),
  ended_at Nullable(DateTime64(3, 'UTC')),
  received_at DateTime64(3, 'UTC'),

  environment LowCardinality(String),
  service LowCardinality(String),
  release LowCardinality(String),
  route String,
  request_id String,
  http_method LowCardinality(String) DEFAULT '',
  http_status_code Nullable(UInt16),
  is_root UInt8 DEFAULT 0,

  tags Map(String, String),
  context_json String,
  ip IPv6 DEFAULT toIPv6('::'),
  user_agent String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(started_at)
ORDER BY (project_id, toDate(started_at), kind, started_at, trace_id, external_span_id, span_id)
TTL toDateTime(started_at) + INTERVAL 120 DAY DELETE
SETTINGS
  index_granularity = 8192,
  non_replicated_deduplication_window = 10000;

-- Additive evolution for installations that created spans_raw from schema v1.
ALTER TABLE logister.spans_raw ADD COLUMN IF NOT EXISTS projection_version UInt64 DEFAULT 1;
ALTER TABLE logister.spans_raw ADD COLUMN IF NOT EXISTS identity_checksum UInt128 DEFAULT 0;
ALTER TABLE logister.spans_raw ADD COLUMN IF NOT EXISTS http_method LowCardinality(String) DEFAULT '';
ALTER TABLE logister.spans_raw ADD COLUMN IF NOT EXISTS http_status_code Nullable(UInt16);
ALTER TABLE logister.spans_raw ADD COLUMN IF NOT EXISTS is_root UInt8 DEFAULT 0;
ALTER TABLE logister.spans_raw MODIFY TTL toDateTime(started_at) + INTERVAL 120 DAY DELETE;

-- Logical typed facts. LIMIT 1 BY is intentionally ordered by the stable source
-- version and acceptance timestamp. These views, not the append tables, own
-- analytical semantics under delivery replay.
CREATE VIEW IF NOT EXISTS logister.event_facts_v2 AS
SELECT *
FROM logister.events_raw
ORDER BY projection_version DESC, received_at DESC
LIMIT 1 BY project_id, event_id;

CREATE VIEW IF NOT EXISTS logister.span_facts_v2 AS
SELECT *
FROM logister.spans_raw
ORDER BY projection_version DESC, received_at DESC
LIMIT 1 BY project_id, span_id;

-- General signal counts used by dashboard and Explorer. These are normal views over
-- deduplicated facts: materialized views fed directly from an at-least-once append
-- table would permanently double-count an ambiguous replay.
CREATE VIEW IF NOT EXISTS logister.event_facts_1m_v2 AS
SELECT
  toStartOfMinute(occurred_at) AS bucket,
  project_id,
  event_type,
  level,
  environment,
  service,
  release,
  count() AS event_count,
  max(occurred_at) AS latest_event_at
FROM logister.event_facts_v2
GROUP BY bucket, project_id, event_type, level, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.event_facts_1h_v2 AS
SELECT
  toStartOfHour(occurred_at) AS bucket,
  project_id,
  event_type,
  level,
  environment,
  service,
  release,
  count() AS event_count,
  max(occurred_at) AS latest_event_at
FROM logister.event_facts_v2
GROUP BY bucket, project_id, event_type, level, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.metric_facts_1m_v2 AS
SELECT
  toStartOfMinute(occurred_at) AS bucket,
  project_id,
  metric_name,
  metric_unit,
  environment,
  service,
  release,
  count() AS event_count,
  countIf(metric_value IS NOT NULL) AS value_count,
  sumIf(metric_value, metric_value IS NOT NULL) AS value_sum,
  avgIf(metric_value, metric_value IS NOT NULL) AS value_avg,
  quantileTDigestIf(0.95)(metric_value, metric_value IS NOT NULL) AS value_p95
FROM logister.event_facts_v2
WHERE event_type = 'metric'
GROUP BY bucket, project_id, metric_name, metric_unit, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.metric_facts_1h_v2 AS
SELECT
  toStartOfHour(occurred_at) AS bucket,
  project_id,
  metric_name,
  metric_unit,
  environment,
  service,
  release,
  count() AS event_count,
  countIf(metric_value IS NOT NULL) AS value_count,
  sumIf(metric_value, metric_value IS NOT NULL) AS value_sum,
  avgIf(metric_value, metric_value IS NOT NULL) AS value_avg,
  quantileTDigestIf(0.95)(metric_value, metric_value IS NOT NULL) AS value_p95
FROM logister.event_facts_v2
WHERE event_type = 'metric'
GROUP BY bucket, project_id, metric_name, metric_unit, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.transaction_facts_1m_v2 AS
SELECT
  toStartOfMinute(occurred_at) AS bucket,
  project_id,
  transaction_name,
  transaction_status,
  environment,
  service,
  release,
  count() AS transaction_count,
  countIf(duration_ms IS NOT NULL) AS duration_count,
  avgIf(duration_ms, duration_ms IS NOT NULL) AS duration_avg,
  quantileTDigestIf(0.95)(duration_ms, duration_ms IS NOT NULL) AS duration_p95
FROM logister.event_facts_v2
WHERE event_type = 'transaction'
GROUP BY bucket, project_id, transaction_name, transaction_status, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.transaction_facts_1h_v2 AS
SELECT
  toStartOfHour(occurred_at) AS bucket,
  project_id,
  transaction_name,
  transaction_status,
  environment,
  service,
  release,
  count() AS transaction_count,
  countIf(duration_ms IS NOT NULL) AS duration_count,
  avgIf(duration_ms, duration_ms IS NOT NULL) AS duration_avg,
  quantileTDigestIf(0.95)(duration_ms, duration_ms IS NOT NULL) AS duration_p95
FROM logister.event_facts_v2
WHERE event_type = 'transaction'
GROUP BY bucket, project_id, transaction_name, transaction_status, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.error_occurrences_1h_v2 AS
SELECT
  toStartOfHour(occurred_at) AS bucket,
  project_id,
  error_fingerprint,
  exception_class,
  level,
  environment,
  service,
  release,
  count() AS occurrence_count,
  max(occurred_at) AS last_seen_at
FROM logister.event_facts_v2
WHERE event_type = 'error'
GROUP BY bucket, project_id, error_fingerprint, exception_class, level, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.log_events_1h_v2 AS
SELECT
  toStartOfHour(occurred_at) AS bucket,
  project_id,
  log_severity,
  message,
  environment,
  service,
  release,
  count() AS log_count,
  max(occurred_at) AS latest_log_at
FROM logister.event_facts_v2
WHERE event_type = 'log'
GROUP BY bucket, project_id, log_severity, message, environment, service, release;

CREATE VIEW IF NOT EXISTS logister.check_in_observations_1h_v2 AS
SELECT
  toStartOfHour(occurred_at) AS bucket,
  project_id,
  check_in_slug,
  check_in_status,
  check_in_expected_interval_seconds,
  environment,
  count() AS observation_count,
  max(occurred_at) AS latest_check_in_at
FROM logister.event_facts_v2
WHERE event_type = 'check_in'
GROUP BY bucket, project_id, check_in_slug, check_in_status,
  check_in_expected_interval_seconds, environment;

CREATE VIEW IF NOT EXISTS logister.request_span_facts_1m_v2 AS
SELECT
  toStartOfMinute(started_at) AS bucket,
  project_id,
  environment,
  service,
  release,
  route,
  http_method,
  http_status_code,
  status,
  count() AS request_count,
  avg(duration_ms) AS duration_avg,
  quantileTDigest(0.95)(duration_ms) AS duration_p95
FROM logister.span_facts_v2
WHERE is_root = 1 AND kind IN ('server', 'browser')
GROUP BY bucket, project_id, environment, service, release, route,
  http_method, http_status_code, status;

CREATE VIEW IF NOT EXISTS logister.request_span_facts_1h_v2 AS
SELECT
  toStartOfHour(started_at) AS bucket,
  project_id,
  environment,
  service,
  release,
  route,
  http_method,
  http_status_code,
  status,
  count() AS request_count,
  avg(duration_ms) AS duration_avg,
  quantileTDigest(0.95)(duration_ms) AS duration_p95
FROM logister.span_facts_v2
WHERE is_root = 1 AND kind IN ('server', 'browser')
GROUP BY bucket, project_id, environment, service, release, route,
  http_method, http_status_code, status;
