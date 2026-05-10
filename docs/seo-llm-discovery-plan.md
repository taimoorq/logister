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
- Rails, PostgreSQL, Redis, Sidekiq, SMTP/Amazon SES, optional ClickHouse
- Versioned GHCR Docker images and GitHub Releases
- Runtime support for Ruby, .NET, Python, JavaScript/TypeScript, and CFML

## Work Plan

1. Standardize the core product phrase across the homepage, README, docs, and AI-readable context.
2. Add intent pages for high-value discovery paths:
   - Self-hosted error monitoring
   - Sentry alternative
   - Bugsnag alternative
   - Bugzilla alternative
   - Rails error monitoring
   - Python error monitoring
   - .NET / ASP.NET Core error monitoring
   - JavaScript / TypeScript error monitoring
   - ColdFusion / CFML error monitoring
   - Docker and GHCR self-hosting
   - Error assignment and team triage
   - Amazon SES error alert emails and digests
3. Expand LLM-readable files:
   - Keep `/llms.txt` concise and curated.
   - Add `/llms-full.txt` as a fuller product, operations, licensing, and comparison context file.
4. Keep structured data accurate and visible:
   - `SoftwareApplication` on the product homepage.
   - `Organization`, `WebSite`, `CollectionPage`, `TechArticle`, and `BreadcrumbList` on docs pages where appropriate.
   - Avoid schema claims that are not visible in the page content.
5. Tune robots and discovery files:
   - Allow search and user-request crawlers where we want citations and discovery.
   - Keep private app, admin, and API areas out of public indexing.
   - List `llms.txt`, `llms-full.txt`, and sitemaps clearly.
6. Strengthen GitHub and release discoverability:
   - Keep README focused on self-hosting, GHCR images, docs, SDKs, license, and trademark rules.
   - Use GitHub topics for self-hosted error monitoring, alternatives, Rails, Redis, PostgreSQL, Sidekiq, Docker, and observability.
7. Measure:
   - Google Search Console and Bing Webmaster Tools.
   - Cloudflare logs for AI crawler traffic.
   - Referrers from AI answer engines and search.
   - GitHub stars, forks, releases, GHCR pulls, SDK installs, and docs-to-self-hosting clicks.

## Current First Pass

- Standardize the core phrase.
- Add the first intent pages for self-hosted error monitoring and major comparison searches.
- Add runtime intent pages for Rails, Python, .NET / ASP.NET Core, JavaScript / TypeScript, and CFML error monitoring.
- Add operational intent pages for Docker/GHCR self-hosting, team error assignment, and Amazon SES alert emails or digest summaries.
- Add `llms-full.txt` to the app and docs surfaces.
- Wire new docs pages into the docs index, sitemap, robots, and tests.
- Update GitHub repository description, homepage, and topics so repository discovery matches the public positioning.
