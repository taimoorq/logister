# SEO and LLM Discovery Plan

## Goal

Make Logister easy for people, search engines, and AI assistants to understand as an open source, self-hosted error monitoring and bug triage app for teams that want a forkable alternative to Bugsnag, Sentry, and Bugzilla-style workflows.

## Core Positioning

Use this sentence as the stable product definition across the homepage, README, docs, release notes, `llms.txt`, GitHub metadata, and package surfaces:

> Logister is an open source, self-hosted error monitoring and bug triage app for teams that want a forkable alternative to Bugsnag, Sentry, and Bugzilla-style workflows.

Supporting phrases can vary naturally, but should consistently reinforce:

- Open source and forkable code
- Self-hosted deployment first
- Error monitoring and grouped bug triage
- Team ownership, assignment, and status workflows
- Rails, PostgreSQL, Redis, Sidekiq, SMTP/Amazon SES, optional S3-compatible archive storage, optional ClickHouse
- Versioned GHCR and Docker Hub images plus GitHub Releases
- Runtime support for Ruby, .NET, Python, JavaScript/TypeScript, Android, iOS, and CFML

## Completed Work Plan

1. Done: Standardize the core product phrase across the homepage, README, docs, release notes, GitHub-facing docs, and AI-readable context.
2. Done: Add intent pages for high-value discovery paths:
   - Self-hosted error monitoring
   - Sentry alternative
   - Bugsnag alternative
   - Bugzilla alternative
   - Rails error monitoring
   - Python error monitoring
   - .NET / ASP.NET Core error monitoring
   - JavaScript / TypeScript error monitoring
   - Android error monitoring
   - iOS error monitoring
   - ColdFusion / CFML error monitoring
   - Docker registry self-hosting
   - Error assignment and team triage
   - Amazon SES error alert emails and digests
3. Done: Expand LLM-readable files:
   - Keep `/llms.txt` concise and curated.
   - Add `/llms-full.txt` as a fuller product, operations, licensing, and comparison context file.
4. Done: Keep structured data accurate and visible:
   - `SoftwareApplication` on the product homepage.
   - `Organization`, `WebSite`, `CollectionPage`, `TechArticle`, and `BreadcrumbList` on docs pages where appropriate.
   - Avoid schema claims that are not visible in the page content.
5. Done: Tune robots and discovery files:
   - Allow search and user-request crawlers where we want citations and discovery.
   - Keep private app, admin, and API areas out of public indexing.
   - List `llms.txt`, `llms-full.txt`, and sitemaps clearly.
6. Done: Strengthen GitHub and release discoverability:
   - Keep README focused on self-hosting, registry images, docs, SDKs, license, and trademark rules.
   - Use GitHub topics for self-hosted error monitoring, alternatives, Rails, Redis, PostgreSQL, Sidekiq, Docker, and observability.
7. Done: Measure:
   - Google Search Console and Bing Webmaster Tools.
   - Cloudflare logs for AI crawler traffic.
   - Referrers from AI answer engines and search.
   - GitHub stars, forks, releases, GHCR and Docker Hub pulls, SDK installs, and docs-to-self-hosting clicks.
   - Use [seo-llm-measurement-runbook.md](seo-llm-measurement-runbook.md) after each public release or major docs update.

## Implementation Record

- Standardize the core phrase.
- Add the first intent pages for self-hosted error monitoring and major comparison searches.
- Add runtime intent pages for Rails, Python, .NET / ASP.NET Core, JavaScript / TypeScript, Android, iOS, and CFML error monitoring.
- Add operational intent pages for Docker registry self-hosting, team error assignment, and Amazon SES alert emails or digest summaries.
- Add `llms-full.txt` to the app and docs surfaces.
- Wire new docs pages into the docs index, sitemap, robots, and tests.
- Update GitHub repository description, homepage, and topics so repository discovery matches the public positioning.
- Add a measurement runbook for release-time URL, sitemap, search console, AI crawler, GitHub, container registry, and SDK package checks.

## Release Maintenance Checklist

Use this short checklist whenever a future release changes product positioning, supported runtimes, infrastructure, distribution, licensing, brand policy, or public docs:

1. Update the homepage, README, Cloudflare docs, `llms.txt`, `llms-full.txt`, release plan, and changelog with the same current release and product language.
2. Add any new public docs pages to `cloudflare-docs/sitemap.xml`, `cloudflare-docs/llms.txt`, `cloudflare-docs/llms-full.txt`, `public/llms.txt`, and `public/llms-full.txt` when relevant.
3. Keep page-visible copy and structured data aligned. Do not add schema claims that the visible page does not support.
4. Keep `robots.txt` focused on public discovery while excluding private app, admin, and API surfaces.
5. Confirm GitHub repository description, homepage, topics, release notes, GHCR and Docker Hub package visibility, and SDK package pages still match the current positioning.
6. Run [seo-llm-measurement-runbook.md](seo-llm-measurement-runbook.md) after production and docs deploys.

## Finished State

This plan is complete for the `v1.1.0` positioning release. Future SEO and LLM work should start from measurement data: search queries, crawler logs, docs referrers, GitHub/GHCR/Docker Hub/package signals, and questions from self-hosters.
