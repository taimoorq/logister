# Rails Architecture Pattern Review Plan

Status: Draft for review  
Created: 2026-06-26  
Owner: Logister maintainers

## Purpose

Review the Rails app's current architecture and decide whether Logister needs a more explicit design pattern to keep feature work consistent, testable, and reliable as the product grows.

This is a planning artifact. Once the decision is made and implemented, keep the durable rules in `AGENTS.md`, tests, and focused runbooks, then remove or archive this plan.

## Initial Assessment

Logister already follows a Rails-first architecture: server-rendered views, Hotwire for page updates, models for persistence and core invariants, service objects for cross-model behavior, presenters for event-specific display logic, and jobs for async work.

The app does not appear to need a heavyweight pattern framework or a new gem right now. The stronger need is a written taxonomy for the patterns already emerging:

- Active Record models own persistence, associations, validations, scopes, and small domain invariants.
- Commands own writes, external side effects, job orchestration, and idempotency-sensitive workflows.
- Queries/reports own read-heavy aggregation, filtering, SQL/Arel, and cache-friendly payload construction.
- Normalizers/validators/builders own pure transformation or validation outside Active Record callbacks.
- Presenters own view-facing formatting, labels, and payload shape.
- Controller concerns own HTTP plumbing that is genuinely shared by controllers, not domain behavior.

The likely pattern to consider is a lightweight Rails service taxonomy, possibly "CQRS-lite" for the read-heavy areas. In practice that means clearer naming and boundaries, not a separate framework.

## Evidence From Current Code

Observed strengths:

- Controllers generally delegate substantial work to services, concerns, models, and presenters.
- There is already a clear `.call` service idiom in places such as `ErrorGroupingService`, `Github::IssuePayload`, `ProjectDeploymentContext`, and notification dispatching.
- Event presenters are already separated under `app/presenters/project_events`.
- Request and service specs cover many important flows.
- Recent uncommitted work appears to be moving non-ActiveRecord domain objects from `app/models` into `app/services`, which is directionally consistent with Rails conventions.

Observed pressure points:

- Several read-heavy classes are large and multi-purpose, especially `ProjectInsights`, `Dashboard`, `ProjectPerformance`, archive search/overview, and transaction browsing.
- Some services mix SQL construction, domain aggregation, parameter normalization, and view/API payload shaping in one class.
- `ClientSubmissionMonitoring` is a controller concern with authentication, diagnostics, rate limiting, mobile-token enforcement, payload summarization, and response rendering in one place.
- Some specs still live under `spec/models` for classes that now live under `app/services`; that blurs the architectural signal and may hide fixture/type assumptions.
- `Project.stats_for` and related aggregate helpers are still on the `Project` model even though they behave more like dashboard/index queries.
- The service layer uses several shapes: all-class-method services, instance `.call` services, builder-like objects with many readers, validators mutating model errors, and report objects returning hashes. That is workable, but undocumented.

## Design Pattern Candidates

### Option A: Document The Existing Service Object Pattern

Keep all non-model app behavior in `app/services`, but require names to reveal responsibility:

- `*Command` or action-oriented names for writes and side effects.
- `*Query`, `*Report`, `*Overview`, or `*Browser` for read models.
- `*Payload`, `*Builder`, `*Normalizer`, or `*Validator` for transformation/validation.
- `*Presenter` remains under `app/presenters`.

This is the lowest-cost option and probably the default unless the review finds stronger pain.

### Option B: Add Explicit `app/queries` And `app/commands`

Move read-heavy aggregators to `app/queries` and write workflows to `app/commands`. This makes architecture easier to scan, but adds another convention to maintain.

Use this only if naming inside `app/services` is not enough.

### Option C: Domain Namespaces Under `app/services`

Group complex product areas into folders such as `ProjectInsights::Catalog`, `ProjectInsights::Dashboard`, `ProjectInsights::MetricSeries`, or `ClientSubmissions::Authenticator`.

This is useful for the biggest classes because it reduces file size while staying close to existing Rails autoloading and naming patterns.

### Option D: Operation/Interactor Framework

Adopt a formal operation pattern or gem.

This should be rejected unless we find repeated cross-cutting needs that Rails services cannot handle: standardized rollback chains, typed results everywhere, shared validation pipelines, or complex workflow composition. Current evidence does not point there.

## Recommended Hypothesis

Start with Option A plus selective Option C.

Do not introduce a new framework. Codify a small service taxonomy, then pilot it on one read-heavy area and one request/side-effect area:

- Read-heavy pilot: split `ProjectInsights` into smaller namespaced query/report components.
- Request/side-effect pilot: split `ClientSubmissionMonitoring` into credential authentication, rate limiting, diagnostics, mobile-token policy, and response helpers.

If those pilots still feel awkward after tests are green, reconsider `app/queries` / `app/commands`.

## Review Plan

### 1. Baseline The App

- Capture top files by size in controllers, concerns, models, services, presenters, jobs, and specs.
- List current public service entrypoints and whether they use class methods, instance `.call`, readers, or mutable model state.
- Run the relevant test suite and static checks before making structural changes.
- Note the active uncommitted refactor before editing, so user work is not accidentally overwritten.

Deliverable: short inventory table in this document.

### 2. Classify Existing Objects

For each non-trivial model, controller concern, and service, classify it as one primary role:

- Model
- Command
- Query/report
- Builder/normalizer
- Validator/policy
- Presenter
- Controller HTTP plumbing
- Job orchestration

Flag anything with more than one primary role.

Deliverable: classification table with "keep", "rename", "split", or "move spec" recommendations.

### 3. Review Reliability Boundaries

Check the areas most likely to create production bugs:

- Transaction boundaries around multi-record writes.
- Idempotency for jobs, retries, ingests, notifications, and GitHub operations.
- Authorization and project access checks.
- Rate-limit behavior and fail-open/fail-closed choices.
- Cache key dimensions and cache invalidation windows.
- SQL/Arel safety, especially hand-built query fragments.
- Time-window behavior around `Time.current`, zones, and bucketed reports.
- Error handling for optional infrastructure such as ClickHouse, Redis, S3, GitHub, and email.

Deliverable: reliability risk list with owner class and proposed pattern boundary.

### 4. Decide The Pattern Rules

Make explicit decisions for:

- Where read models live: `app/services` with suffixes vs `app/queries`.
- Where write workflows live: action-named service classes vs `app/commands`.
- Whether every service should expose `.call`, or whether reader-style objects are acceptable for UI state.
- Whether services should return plain hashes, `Data.define` result objects, ActiveRecord relations, or rendered-ready payloads.
- Spec location and type metadata for non-ActiveRecord classes.
- Size and responsibility thresholds that trigger splitting.

Suggested thresholds:

- Split a service above about 300 lines when it has multiple public entrypoints or mixes SQL, transformation, and presentation.
- Keep a model method if it protects one record's invariant or a small association rule.
- Move a model class method to a query/report object when it aggregates across many records for a screen.
- Keep a controller concern only when it is HTTP-specific or reused by multiple controllers.

Deliverable: accepted architecture rules ready to move into `AGENTS.md`.

### 5. Pilot The Rules

Use focused refactors, not a broad rewrite.

Candidate pilots:

- `ProjectInsights`: extract catalog/filter discovery, standard metric aggregation, custom metric aggregation, bucket/time helpers, and response assembly.
- `ClientSubmissionMonitoring`: extract credential authentication, rate limiting, mobile token policy, and diagnostic payload building.
- `Dashboard`: consider `Dashboard::Summary` and `Dashboard::Explorer` or equivalent query/report classes.
- `Project.stats_for`: consider a `ProjectStats` or project index query object.
- Moved service specs: relocate `spec/models/dashboard_spec.rb`, `spec/models/project_performance_spec.rb`, `spec/models/project_archive_overview_spec.rb`, `spec/models/project_archive_investigation_search_spec.rb`, and `spec/models/project_github_integration_state_spec.rb` only after fixture/type behavior is confirmed.

Deliverable: one or two merged examples that prove the rules improve readability without breaking Rails simplicity.

### 6. Codify And Clean Up

- Update `AGENTS.md` with the final service taxonomy.
- Update spec conventions if service specs need explicit fixture support.
- Rename or move specs to mirror class locations once stable.
- Add small examples for the preferred `.call`, query/report, validator, and presenter shapes.
- Remove this planning document after the durable guidance is captured and the migration checklist is complete.

Deliverable: final architecture guidance in durable repo docs, with stale planning artifacts removed.

## Decision Criteria

Adopt or refine a pattern only if it:

- Makes future features easier to place without debate.
- Reduces mixed responsibilities in the largest files.
- Improves isolated testability without requiring many integration-only tests.
- Makes reliability boundaries more explicit for writes, retries, rate limits, and external calls.
- Stays idiomatic Rails and avoids ceremony.
- Does not force small model methods or simple controllers into unnecessary abstractions.

## Open Questions

- Should Logister add `app/queries` and `app/commands`, or keep the simpler `app/services` convention with explicit names?
- Should service specs get a first-class RSpec type or simply use normal specs with explicit fixture setup where needed?
- Should result objects become standard for commands that can fail, or stay limited to areas where callers need structured outcomes?
- What file-size or responsibility threshold should become a hard convention versus a review guideline?
- Should `ProjectInsights` be the first pilot, or should we start with the smaller dashboard/performance classes to validate the pattern with less churn?

## Next Review Session Agenda

1. Review this plan and adjust the pattern hypothesis.
2. Decide whether current model-to-service moves should also move/retag specs.
3. Choose one pilot refactor.
4. Define the tests that must pass before and after the pilot.
5. After the pilot, decide whether to update `AGENTS.md` immediately or run a second pilot first.
