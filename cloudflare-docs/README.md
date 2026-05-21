# Cloudflare Docs

This directory contains a standalone static version of the Logister documentation intended for deployment on Cloudflare Pages.

## Structure

- `index.html` and subdirectory `index.html` files provide the static documentation pages.
- `assets/site.css` contains the docs-specific theme and layout styles.
- `assets/site.js` provides mobile navigation, collapsible sidebar sections, analytics loading, and copy-to-clipboard behavior for code blocks.
- `functions/assets/analytics-config.js/index.js` serves runtime analytics and Probo Cookie Banner configuration from Cloudflare Pages secrets.
- `assets/logister-logo.svg` is copied locally so the docs do not depend on the app asset pipeline.

## Suggested Cloudflare Pages setup

Use `cloudflare-docs` as the project root or output directory and deploy it as a plain static site. Before deploying, run the lightweight metadata build so `sitemap.xml` and `robots.txt` use the configured docs host instead of assuming the official production domain.

```bash
LOGISTER_DOCS_URL=https://docs.example.com bin/build-cloudflare-docs
```

`LOGISTER_DOCS_URL` defaults to `https://docs.logister.org`. `DOCS_SITEMAP_LASTMOD` can be set when you want to pin sitemap `lastmod` during a release.

## Local preview

To preview the static docs locally with Cloudflare Pages behavior, run this from the repo root:

```bash
wrangler pages dev cloudflare-docs
```

That serves the `cloudflare-docs/` directory locally so you can verify layout, navigation, copy buttons, sitemap, robots, and other static-site behavior before deploying.

## GitHub Actions deployment

The repository now includes a dedicated workflow at `.github/workflows/cloudflare-docs-deploy.yml`.

It deploys automatically when changes land on `main` under:

- `cloudflare-docs/**`

Set these GitHub repository settings before enabling it:

- Secret: `CLOUDFLARE_API_TOKEN`
- Secret: `CLOUDFLARE_ACCOUNT_ID`
- Variable: `CLOUDFLARE_PAGES_PROJECT`

The workflow runs `bin/build-cloudflare-docs` first, then deploys this directory directly with:

- `wrangler pages deploy cloudflare-docs --project-name=<project>`

Optional GitHub repository variables:

- `LOGISTER_DOCS_URL` sets the public docs host used in generated metadata.
- `DOCS_SITEMAP_LASTMOD` pins the sitemap date for a release.

## Runtime docs configuration

Set optional docs runtime values as Cloudflare Pages secrets:

```bash
wrangler pages secret put DOCS_PROBO_COOKIE_BANNER_ID --project-name=logister-docs
wrangler pages secret put DOCS_PROBO_COOKIE_BANNER_BASE_URL --project-name=logister-docs
wrangler pages secret put DOCS_PROBO_COOKIE_BANNER_POSITION --project-name=logister-docs
wrangler pages secret put DOCS_ANALYTICS_COOKIE_CATEGORY --project-name=logister-docs
wrangler pages secret put DOCS_GOOGLE_TAG_ID --project-name=logister-docs
wrangler pages secret put DOCS_CLOUDFLARE_WEB_ANALYTICS_TOKEN --project-name=logister-docs
```

Docs analytics will not load unless both `DOCS_PROBO_COOKIE_BANNER_ID` and `DOCS_PROBO_COOKIE_BANNER_BASE_URL` are configured. Values served through `/assets/analytics-config.js` are visible to browsers at runtime, so do not put server-only credentials there.

For the Rails app itself, keep using `.env.sample` as the operator map. The public deployment page includes a full entry-by-entry reference for Rails, PostgreSQL, Redis, Sidekiq, Amazon SES SMTP, ClickHouse, Turnstile, analytics, and Cloudflare Pages docs variables:

- https://docs.logister.org/deployment/#env-reference

## Current scope

This static export mirrors the current public docs pages from the main Logister app:

- Overview
- Getting started
- Product guide
- Use cases and comparisons
- Self-hosted error monitoring
- Sentry, Bugsnag, and Bugzilla alternatives
- Rails, Python, .NET, JavaScript, and CFML error monitoring use cases
- Docker registry self-hosting
- Error assignment and team triage
- Amazon SES alert emails and digests
- Self-hosting
- Local development
- Deployment config
- ClickHouse
- HTTP API
- Ruby integration
- .NET integration
- Python integration
- JavaScript integration
- CFML integration
- `llms.txt` and `llms-full.txt`

## Updating the docs

When you add or change docs pages in this folder:

- update any repeated sidebar or footer integration links if navigation changed
- keep sidebar groups as `<div class="sidebar-group"><p class="sidebar-label">...</p>...</div>`; `assets/site.js` turns those groups into accessible collapsible sections at runtime
- run `bin/build-cloudflare-docs` when you add a new public page so `sitemap.xml` and `robots.txt` stay aligned
- preview locally with `wrangler pages dev cloudflare-docs`
- deploy through the GitHub Actions workflow or `wrangler pages deploy cloudflare-docs --project-name=<project>`
