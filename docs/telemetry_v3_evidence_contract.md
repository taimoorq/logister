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
- When session timing is enabled, send `context.session.started_at` from the
  same session owner as `context.session.id`. The server derives early-session
  age only for an exact compatible event clock.
- Apple sampled diagnostics may send `context.diagnostic.call_stack_tree` with
  bounded stacks, nested frames, roles, attribution, and sample counts. Typed
  measurements use `{ value, unit, source_field }` with canonical `seconds` or
  `bytes`. Keep raw addresses and relative offsets as hexadecimal strings.
- Fatality is evidence, not a default: omit it for excessive CPU, disk-write,
  and slow-launch diagnostics unless the source explicitly proves termination.
- Android historical exits may send canonical `last_pss`/`last_rss` byte
  measurements labeled `last_system_sample`. ANRs may include a bounded
  `context.diagnostic.thread_dump` containing only structured thread names and
  Java/Kotlin frames; raw trace text, command lines, and lock annotations are
  not part of the ordinary event contract.
- Android live uncaught exceptions may send a bounded
  `context.error.thread_name` with `thread_role: crashed`. Manual reports use
  `reporting`; historical ANR thread dumps use sampled/attributed roles.

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
