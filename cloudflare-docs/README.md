# Cloudflare Docs

This directory contains a standalone static version of the Logister documentation intended for deployment on Cloudflare Pages.

## Structure

- `index.html` and subdirectory `index.html` files provide the static documentation pages.
- `assets/site.css` contains the docs-specific theme and layout styles.
- `assets/site.js` provides mobile navigation and copy-to-clipboard behavior for code blocks.
- `assets/logister-logo.svg` is copied locally so the docs do not depend on the Rails asset pipeline.

## Suggested Cloudflare Pages setup

Use `cloudflare-docs` as the project root or output directory and deploy it as a plain static site.

No build step is required unless you later decide to add a static-site generator on top of this folder.

## GitHub Actions deployment

The repository now includes a dedicated workflow at `.github/workflows/cloudflare-docs-deploy.yml`.

It deploys automatically when changes land on `main` under:

- `cloudflare-docs/**`

Set these GitHub repository settings before enabling it:

- Secret: `CLOUDFLARE_API_TOKEN`
- Variable: `CLOUDFLARE_ACCOUNT_ID`
- Variable: `CLOUDFLARE_PAGES_PROJECT`

The workflow deploys this directory directly with:

- `wrangler pages deploy cloudflare-docs --project-name=<project>`

## Current scope

This static export mirrors the current public docs pages from the Rails app:

- Overview
- Getting started
- Self-hosting
- Local development
- Deployment config
- ClickHouse
- HTTP API
- Ruby integration
- CFML integration
