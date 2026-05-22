-- 1) Event volume for charting (1-minute buckets)
SELECT
  bucket,
  sumMerge(count) AS total_events
FROM logister.events_1m
WHERE project_id = {project_id:UInt64}
  AND bucket >= now() - INTERVAL 24 HOUR
GROUP BY bucket
ORDER BY bucket;

-- 2) Error rate by minute
SELECT
  bucket,
  sumMergeIf(count, event_type = 'error') AS errors,
  sumMerge(count) AS total,
  if(total = 0, 0, errors / total) AS error_rate
FROM logister.events_1m
WHERE project_id = {project_id:UInt64}
  AND bucket >= now() - INTERVAL 24 HOUR
GROUP BY bucket
ORDER BY bucket;

-- 3) Top fingerprints in last 24h
SELECT
  fingerprint,
  anyLast(message) AS sample_message,
  count() AS occurrences,
  max(occurred_at) AS last_seen
FROM logister.events_raw
WHERE project_id = {project_id:UInt64}
  AND event_type = 'error'
  AND occurred_at >= now() - INTERVAL 24 HOUR
GROUP BY fingerprint
ORDER BY occurrences DESC
LIMIT 20;

-- 4) Regressions: fingerprints newly active in last 24h
SELECT
  current.fingerprint,
  current.current_count,
  current.last_seen
FROM
(
  SELECT
    fingerprint,
    count() AS current_count,
    max(occurred_at) AS last_seen
  FROM logister.events_raw
  WHERE project_id = {project_id:UInt64}
    AND event_type = 'error'
    AND occurred_at >= now() - INTERVAL 24 HOUR
  GROUP BY fingerprint
) AS current
LEFT JOIN
(
  SELECT DISTINCT fingerprint
  FROM logister.events_raw
  WHERE project_id = {project_id:UInt64}
    AND event_type = 'error'
    AND occurred_at >= now() - INTERVAL 14 DAY
    AND occurred_at < now() - INTERVAL 24 HOUR
) AS history
ON current.fingerprint = history.fingerprint
WHERE history.fingerprint IS NULL
ORDER BY current.current_count DESC
LIMIT 20;

-- 5) Error breakdown by environment and release
SELECT
  environment,
  release,
  count() AS errors
FROM logister.events_raw
WHERE project_id = {project_id:UInt64}
  AND event_type = 'error'
  AND occurred_at >= now() - INTERVAL 7 DAY
GROUP BY environment, release
ORDER BY errors DESC
LIMIT 50;

-- 6) Slowest request/page-load root spans for stacked load-time charts
SELECT
  trace_id,
  anyLast(name) AS request_name,
  anyLast(route) AS route,
  anyLast(request_id) AS request_id,
  max(duration_ms) AS duration_ms,
  min(started_at) AS started_at
FROM logister.spans_raw
WHERE project_id = {project_id:UInt64}
  AND kind IN ('server', 'browser')
  AND parent_span_id = ''
  AND started_at >= now() - INTERVAL 24 HOUR
GROUP BY trace_id
ORDER BY duration_ms DESC
LIMIT 25;

-- 7) Span timing segments for the selected request roots
SELECT
  trace_id,
  kind,
  sum(duration_ms) AS duration_ms
FROM logister.spans_raw
WHERE project_id = {project_id:UInt64}
  AND trace_id IN ({trace_ids:Array(String)})
  AND parent_span_id != ''
GROUP BY trace_id, kind
ORDER BY trace_id, duration_ms DESC;
