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

## Maintenance Checklist

When adding a new public docs page:

1. Link it from the docs homepage if it starts or completes a common task.
2. Add it to the appropriate sidebar group.
3. Add it to `bin/build-cloudflare-docs` preferred paths when order matters in the sitemap.
4. Update `cloudflare-docs/llms.txt` and `cloudflare-docs/llms-full.txt` when the page is important for AI or search discovery.
5. Update `public/llms.txt` and `public/llms-full.txt` when the public app should point crawlers to the new docs page.
6. Run `bin/build-cloudflare-docs` before deploying the static docs.
