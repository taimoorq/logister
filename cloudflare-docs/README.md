# Cloudflare Docs

This directory contains a standalone static version of the Logister documentation intended for deployment on Cloudflare Pages.

## Structure

- `index.html` and subdirectory `index.html` files provide the static documentation pages.
- `assets/site.css` contains the docs-specific theme and layout styles.
- `assets/site.js` provides mobile navigation and copy-to-clipboard behavior for code blocks.
- `functions/assets/analytics-config.js/index.js` serves runtime analytics and Probo Cookie Banner configuration from Cloudflare Pages secrets.
- `assets/logister-logo.svg` is copied locally so the docs do not depend on the app asset pipeline.

## Suggested Cloudflare Pages setup

Use `cloudflare-docs` as the project root or output directory and deploy it as a plain static site.

No build step is required unless you later decide to add a static-site generator on top of this folder.

## Local preview

To preview the static docs locally with Cloudflare Pages behavior, run this from the repo root:

```bash
wrangler pages dev cloudflare-docs
```

That serves the `cloudflare-docs/` directory locally so you can verify layout, navigation, copy buttons, and other static-site behavior before deploying.

## GitHub Actions deployment

The repository now includes a dedicated workflow at `.github/workflows/cloudflare-docs-deploy.yml`.

It deploys automatically when changes land on `main` under:

- `cloudflare-docs/**`

Set these GitHub repository settings before enabling it:

- Secret: `CLOUDFLARE_API_TOKEN`
- Secret: `CLOUDFLARE_ACCOUNT_ID`
- Variable: `CLOUDFLARE_PAGES_PROJECT`

The workflow deploys this directory directly with:

- `wrangler pages deploy cloudflare-docs --project-name=<project>`

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

## Current scope

This static export mirrors the current public docs pages from the main Logister app:

- Overview
- Getting started
- Product guide
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

## Updating the docs

When you add or change docs pages in this folder:

- update any repeated sidebar or footer integration links if navigation changed
- update `sitemap.xml` when you add a new public page
- preview locally with `wrangler pages dev cloudflare-docs`
- deploy through the GitHub Actions workflow or `wrangler pages deploy cloudflare-docs --project-name=<project>`
