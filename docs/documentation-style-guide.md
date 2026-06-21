# Documentation Style Guide

Use this guide when adding or rewriting public Logister docs. The goal is a practical self-hosted product manual: clear sections, short explanations, direct setup paths, and enough operational detail for someone running the app themselves.

## Information Architecture

Organize the docs around the user's path through Logister:

1. Documentation: what Logister is, why teams self-host it, and which feature or comparison page to read first.
2. Installation: how to get an instance running locally or in production.
3. Configuration: the settings and optional services an operator can enable after the baseline works.
4. Usage: projects, API keys, triage, event details, Insights, monitors, notifications, sharing, and lifecycle actions.
5. Integrations: runtime-specific setup for SDKs and direct HTTP clients.
6. API reference: exact request and response contracts for custom clients.
7. Troubleshooting: narrow, symptom-driven checks for common setup and ingestion problems.

The docs homepage should work as a table of contents. Feature pages should go deeper, but they should still keep this reader path in mind.

## Audience And Objectives

Start every new or rewritten page by naming the reader and their goal. Logister docs usually serve one of these readers:

- Self-hosted operators getting an instance running or keeping it healthy.
- App developers wiring Ruby, .NET, Python, JavaScript, Android, iOS, CFML, Cloudflare Pages, or direct HTTP telemetry.
- Project users triaging errors, reading event context, tuning notifications, reviewing Insights, or changing retention settings.
- Maintainers releasing the app, SDKs, public docs, and discovery files.

Write the page for the reader's immediate job before adding product background. The first screen should tell them whether they are in the right place, what they can accomplish, and what prerequisite they must satisfy first.

Use objectives that can be tested:

- "Send one error and see it in the inbox."
- "Configure SMTP and prove project mail can be delivered."
- "Store Cloudflare Pages importer settings without pasting raw tokens into Logister."
- "Choose a retention window and verify the worker archived or pruned the expected rows."

Avoid vague objectives such as "learn more about notifications" unless the page is a short hub that routes the reader to the right task.

## Page Template

Most feature or operations pages should follow this order:

1. One sentence that says what the page helps the reader do.
2. A short overview that names the moving pieces.
3. A "Before you start" or "Quick checks" section when prerequisites matter.
4. The main task or concept, explained in plain language.
5. Exact commands, settings, payloads, or UI locations where useful.
6. Common mistakes or failure modes.
7. Links to the next most likely page.

Use tables for choices, status codes, settings, or feature comparisons. Use ordered lists for procedures. Use bullets for checks and guidelines.

## Formats And Visuals

Choose the format that matches the task:

- Use ordered steps for procedures.
- Use tables for choices, settings, permissions, status codes, fields, and support matrices.
- Use code blocks for commands, payloads, config, and SDK snippets. Add copy buttons in static HTML pages when the block is meant to be reused.
- Use screenshots when the UI path or control relationship matters. Screenshots should show the real Logister product state, not generic decoration.
- Match screenshot layout to the job it does. Use full-width figures for broad scan views, dashboards, inboxes, and charts. Use a paired column layout for tall forms, narrow panels, settings cards, or focused controls so the visual can sit next to the explanation. Do not scale a screenshot larger than the UI would reasonably appear in the product.
- Use diagrams only when a flow is hard to explain in text, such as token issuance, webhook callbacks, ingestion paths, or retention jobs.

Screenshots need useful alt text, fixed width and height attributes, and a caption that explains what the reader should look for. After changing screenshots, run `bin/build-cloudflare-docs` so files from `app/assets/images/screenshots/public` are copied into `cloudflare-docs/assets/screenshots`, then check for missing local assets.

## Page Scope And Subpages

Keep each public docs page small enough that a user can understand why they are there before they start reading details. If a feature has multiple reasons a user might visit the page, make the top-level page a routing page and move the detailed instructions into subpages.

Use a hub page when a feature contains several distinct jobs:

- Notifications: setup requirements, error triage, project health, workflow routing, digests and delivery, operational notices.
- Data retention: policy settings, archive storage, archive and prune jobs.
- Source lookup: setup, repository mapping, path/ref diagnostics.
- Integrations: working telemetry path, optional importer or credential settings, troubleshooting.

The hub page should:

1. Name the feature in one sentence.
2. Explain the default behavior and required infrastructure.
3. Show cards or a compact table that maps "I want..." to the right subpage.
4. Link to the next page instead of explaining every field inline.

Each subpage should own one user purpose. It should not repeat the full product tour from the hub. Include only the controls, commands, verification steps, and failure modes needed for that path.

When two settings sound similar, separate them and state the difference plainly. For example, an error milestone alert is about one error group's lifetime count, a single-error volume threshold is about one group crossing a count inside a time window, and a project spike alert is about the whole project becoming noisy.

## Preferred Docs Voice

The public docs should feel like a practical self-hosted product manual, in the same spirit as the Bugsink docs we used as a reference: direct, operational, and written by someone who has actually had to run the service.

Use this style for setup, configuration, integration, and troubleshooting pages:

- Start with what the page helps the reader do.
- Say when the feature is optional, and what still works without it.
- Put self-hosting assumptions in the open: public URL, secret store, worker process, database, Redis, email, or external service access.
- Give exact UI paths, environment variable names, commands, payload fields, permissions, callback URLs, and webhook URLs.
- Prefer least-privilege access guidance when a service needs credentials or installation access.
- Include verification steps that prove the setup worked.
- End with concrete failure modes and the next page to read.

Avoid a marketing-page rhythm. Do not use large value-prop sections, vague "unlock more power" claims, or long lists of benefits without setup details. If a feature is useful, show the behavior a developer or operator will actually see.

## Writing Manner

Write like an experienced maintainer helping another developer operate the system:

- Prefer short paragraphs over broad product copy.
- Lead with the practical answer, then add context.
- Explain feature names the first time they appear.
- Say what Logister does with the data, not just that a feature exists.
- Use "when to use this" and "what to check" language.
- Keep self-hosting front and center; describe the hosted app as secondary when that distinction matters.
- Avoid marketing claims unless the page can prove them with visible product behavior or setup details.
- Avoid dense feature bundles in one sentence. Split into readable pieces.
- Link to the exact guide or anchor that continues the task.

For optional integrations, keep the same shape used by the GitHub App guide:

1. What this enables.
2. What the default behavior is when it is not configured.
3. Before-you-start requirements.
4. Exact setup in the external service and in Logister.
5. Minimum required permissions or secrets.
6. Install, sync, or restart steps.
7. How to verify it worked.
8. Troubleshooting symptoms and likely fixes.

## Feature Explanation Pattern

When explaining a product feature, include:

- What it is: "A project is one monitored app or service."
- Why it exists: "It keeps API keys, events, settings, and team access scoped."
- How users interact with it: "Create it before generating an API key."
- What can go wrong: "Archived projects reject active tokens."
- Where to go next: "Read the getting started or HTTP API guide."

This pattern keeps feature docs useful for new users and operators without turning every page into a long product tour.

## Self-Hosted Operations Pattern

When explaining operations, separate required and optional infrastructure:

- Required baseline: Rails web app, PostgreSQL, Redis, and Sidekiq.
- Recommended production pieces: HTTPS, backups, outbound email, and a secrets store.
- Optional services: ClickHouse, S3-compatible archive storage, Turnstile, analytics, and separate static docs hosting.

Always tell readers which layer they should verify first. Optional services should not look required for a first working install.

## Troubleshooting Pattern

Troubleshooting pages should be symptom-driven:

- Empty inbox
- Rejected event
- Rate limited request
- Missing email
- Worker not processing jobs
- ClickHouse not ready
- Archive export missing

For each symptom, list the likely cause, the specific check, and the page that contains the full reference.

## Freshness And Feedback

Treat docs as the first support surface. A page is not done until it helps the reader confirm success and recover from likely failure.

Include feedback paths where they fit:

- Link to the troubleshooting guide for operational symptoms.
- Link to the relevant GitHub repo or issue tracker for package-specific problems.
- Mention `support@logister.org` only when the reader needs a human support path rather than a product reference.

Keep versioned values close to their source of truth. Prefer generated or checked references over manually repeated strings:

- Ruby package version: `logister-ruby/lib/logister/version.rb`.
- Python package version: `logister-python/pyproject.toml`.
- JavaScript package version: `logister-js/package.json`.
- .NET package versions: `logister-dotnet/src/*/*.csproj`.
- Android package version: `logister-android/gradle.properties`.
- iOS package version: `logister-ios/VERSION`.

When changing SDK or release guidance, update the public docs, SDK README, `llms.txt`, `llms-full.txt`, package links, and release runbooks together. If version references are generated, update the generator and run its check mode instead of hand-editing the output.

## Maintenance Checklist

When adding a new public docs page:

1. Link it from the docs homepage if it starts or completes a common task.
2. Add it to the appropriate sidebar group.
3. Add it to `bin/build-cloudflare-docs` preferred paths when order matters in the sitemap.
4. Update `cloudflare-docs/llms.txt` and `cloudflare-docs/llms-full.txt` when the page is important for AI or search discovery.
5. Update `public/llms.txt` and `public/llms-full.txt` when the public app should point crawlers to the new docs page.
6. Run `bin/build-cloudflare-docs` before deploying the static docs.
7. Check that screenshots, local links, Pagefind content, metadata, and package version references are not stale.
8. Remove completed plan or roadmap docs once the shipped behavior is represented in durable docs, changelog entries, tests, and agent guidance.
