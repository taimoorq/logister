# Telemetry v3 evidence contract

Telemetry v3 is an additive event envelope accepted by `POST /api/v1/ingest_events`
and the NDJSON batch endpoint. The HTTP route remains version 1; `v3` identifies
the mobile telemetry schema carried by the event.

The client owns the immutable event UUID, source evidence, capture time or
reporting interval, diagnostic kind, capture mode, and producer version. The
server owns receipt time, canonical clock precision, normalization metadata,
tenant-scoped idempotency, grouping lifecycle, artifact coverage, and every
symbolication/deobfuscation claim.

Required client rules:

- Generate one UUID when evidence is captured and reuse it for every retry.
- Send `occurred_at` only for an exact source occurrence time.
- For a source reporting period, omit `occurred_at` and send
  `evidence.reporting_period.start` and `.end`.
- Omit both when neither is known; Logister records the evidence as
  `received_only` and does not use receipt proximity for issue regression,
  spikes, deployment causality, or related logs.
- Treat `source`, `kind`, and `capture_mode` as open enums. Unknown values are
  retained and render through a safe fallback.
- Never claim server symbolication/deobfuscation status. Send immutable raw
  frame/binary evidence; Logister derives artifact verification and coverage.

The accepted client envelope is defined in
[`telemetry_v3_evidence.schema.json`](telemetry_v3_evidence.schema.json).
Canonical server evidence is written to `context.telemetry_evidence` with:

- `time.precision`: `exact`, `reporting_interval`, or `received_only`
- `time.received_at`: server receipt time
- source/kind/capture/evidence/identity/fatality facets
- producer SDK/schema/decoder versions
- `normalization.owner: server`

Routine UI, email, and exports use redacted canonical evidence. Original raw
evidence is not part of the normal Raw tab or routine issue export.

