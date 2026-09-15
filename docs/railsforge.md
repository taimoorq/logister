# RailsForge diagnostics

Run diagnostics with the Ruby version in `.ruby-version` and the bundled gem:

```sh
bundle exec railsforge doctor
bundle exec railsforge doctor --format=json > tmp/railsforge.json
```

RailsForge 2.2.0 uses text patterns for security, performance, and method-length
checks. Review the code behind each finding before changing behavior. Its score
does not establish security or correctness; informational suggestions carry no
score penalty.

## Query findings

- Deployment pagination orders by `COALESCE(deployed_at, created_at)` and UUID,
  both descending. Keep that same timestamp expression in the cursor predicate
  and inclusive time filters. The tuple predicate uses fixed SQL and bound cursor
  values; the other predicates use Arel.
- Monitor filters must agree with `CheckInMonitor#status`, including paused/error
  precedence, missing check-ins, the inclusive deadline, and integer truncation
  for odd expected intervals. The fixed deadline expression contains no request
  input; Arel quotes the comparison timestamp.
- Activity discovery uses receipt time (`created_at`) for mobile projects and
  source time (`occurred_at`) for other projects. `ProjectActivityQuery` owns the
  filtering and bounded, preloaded lookup of related error groups.

The request specs in `spec/requests/api/v1/cli_v35_read_api_spec.rb` exercise
timestamp ties, undated deployments, pagination boundaries, and monitor status
boundaries. Activity filtering is covered in `spec/requests/projects_spec.rb`.

## Performance false positives

The analyzer looks for an iteration followed by query-like method names within
five source lines. It does not establish whether the operation is inside the
loop or whether its receiver is an Active Record relation.

Examples from this application:

- Collecting outbox IDs precedes one delivery existence query; it does not query
  once per outbox event.
- Reading activity timestamps precedes one related-event query, which preloads
  error groups.
- Artifact inventory contains materialized value objects. The query preloads
  uploaders; checksum truncation calls `String#first`.
- Setup steps are value objects, grouped in memory by stage.
- `ProjectIntegrationDefinition::DEFINITIONS` is a frozen array of Ruby data,
  not a database table.

Do not add database preloads or replace these operations with database batching
solely to satisfy a text-pattern finding.

## Structural suggestions

Keep extractions aligned with responsibilities: CLI responses and parameters,
batch ingestion, event responses and evidence downloads, monitor recording,
error-group recording, project lifecycle, delivery batch claims, and watermark
progress recording. Preserve transaction boundaries, lease fences, callback
ordering, authorization, and public method visibility when moving this code.

The 15-line method threshold is advisory. Declarative payloads and cohesive
transaction blocks may exceed it. The parser can also miscount Ruby syntax:
for example, it treats `.class` as a block opener and does not fully parse
assignment-form conditionals or singleton method names. The original report
counted the seven-line `CliAccessToken#touch_last_used!` as 73 lines.

Use the real method body, duplication, and domain boundaries to decide whether
an extraction improves the code. Keep remaining informational suggestions visible
in the report; do not suppress them or change thresholds to obtain a score.

## Validation

```sh
bundle exec rails zeitwerk:check
bundle exec rspec --exclude-pattern 'spec/system/**/*_spec.rb'
bundle exec rubocop
bundle exec brakeman --no-pager
```

Live Redis integration examples require the test Redis configuration used by CI.
An unset `REDIS_URL` leaves those examples pending. Ignored local Ruby scripts can
appear in a default RuboCop run even though they are absent from a clean checkout.
