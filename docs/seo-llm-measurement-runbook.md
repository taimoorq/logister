# SEO and LLM Measurement Runbook

Use this after public releases and docs changes to confirm Logister is discoverable as an open source, self-hosted error monitoring and bug triage app. The checks apply to the official Logister project and to public self-hosted forks that use their own branding.

## Release Checklist

Run these checks after a release reaches production and the docs deploy has finished:

- Confirm the homepage, About page, public docs, `llms.txt`, `llms-full.txt`, `robots.txt`, and `sitemap.xml` return `200` responses.
- Confirm the homepage and docs pages use the current product language from [seo-llm-discovery-plan.md](seo-llm-discovery-plan.md).
- Confirm GitHub Releases show the new version as the latest release.
- Confirm the GHCR and Docker Hub packages are public and the versioned Docker image can be pulled without authentication from both registries.
- Confirm `README.md`, `CHANGELOG.md`, public docs, and AI-readable files mention the same current version.

Suggested URL checks:

```bash
curl -sI https://logister.org/
curl -sI https://logister.org/about
curl -sI https://logister.org/llms.txt
curl -sI https://logister.org/llms-full.txt
curl -sI https://logister.org/robots.txt
curl -sI https://logister.org/sitemap.xml
curl -sI https://docs.logister.org/
curl -sI https://docs.logister.org/llms.txt
curl -sI https://docs.logister.org/llms-full.txt
curl -sI https://docs.logister.org/robots.txt
curl -sI https://docs.logister.org/sitemap.xml
```

## Search Console Checks

Submit or resubmit these sitemaps after major public docs changes:

- `https://logister.org/sitemap.xml`
- `https://docs.logister.org/sitemap.xml`

Track these query families in Google Search Console and Bing Webmaster Tools:

- `self-hosted error monitoring`
- `open source error monitoring`
- `open source Sentry alternative`
- `self-hosted Sentry alternative`
- `Bugsnag alternative`
- `Bugzilla alternative for application errors`
- `Rails error monitoring`
- `Python error monitoring`
- `.NET error monitoring`
- `JavaScript error monitoring`
- `CFML error monitoring`
- `Docker self-hosted error monitoring`
- `Amazon SES error alerts`

Record impressions, clicks, average position, indexed pages, sitemap status, and crawl errors for each release cycle.

## AI Crawler Checks

Use Cloudflare logs, Logpush, or provider access logs to check whether AI and search crawlers are fetching the public surfaces. Keep private app, admin, and API routes out of public indexing.

Watch for these user agents or families:

- `GPTBot`
- `ChatGPT-User`
- `OAI-SearchBot`
- `ClaudeBot`
- `Claude-SearchBot`
- `Claude-User`
- `PerplexityBot`
- `Googlebot`
- `Bingbot`
- `Google-Extended`

Useful log fields:

- Hostname
- Path
- Status code
- User agent
- Referer
- Country
- Cache status
- Timestamp

The important paths are `/`, `/about`, `/docs`, `/llms.txt`, `/llms-full.txt`, `/robots.txt`, `/sitemap.xml`, and the public comparison, runtime, and self-hosting docs pages.

## Referral and Self-Hosting Signals

Use privacy-conscious analytics and server logs to understand whether discovery leads to real self-hosting interest. Do not log secrets, API keys, event payloads, or private app paths for marketing analysis.

Track these public-page signals:

- Search and AI answer engine referrers to the homepage, docs home, comparison pages, runtime pages, and Docker registry self-hosting page.
- Clicks from public docs to GitHub source, GitHub Releases, GHCR package, Docker Hub package, and SDK package pages.
- Clicks from comparison pages to getting started, self-hosting, deployment, HTTP API, and integration docs.
- Search Console query growth for the target phrases in this plan.
- GitHub stars, forks, release views, release downloads, issue activity, and discussions from new self-hosters.
- GHCR and Docker Hub image pulls where package visibility and registry reporting make that available.
- SDK package installs and package page traffic for RubyGems, PyPI, npm, and NuGet.

Useful paths to compare after each release:

- `https://docs.logister.org/use-cases/self-hosted-error-monitoring/`
- `https://docs.logister.org/use-cases/sentry-alternative/`
- `https://docs.logister.org/use-cases/bugsnag-alternative/`
- `https://docs.logister.org/use-cases/bugzilla-alternative/`
- `https://docs.logister.org/self-hosting/`
- `https://docs.logister.org/self-hosting/#docker`
- `https://docs.logister.org/deployment/`
- `https://github.com/taimoorq/logister`
- `https://github.com/taimoorq/logister/releases`
- `https://github.com/taimoorq/logister/pkgs/container/logister`

## GitHub And Registry Checks

Use GitHub, GHCR, and Docker Hub as discovery surfaces for self-hosters:

- Confirm repository description and topics still match the current product positioning.
- Confirm the latest release body comes from the top changelog entry.
- Confirm the GHCR image has version, `latest`, and short-SHA tags.
- Confirm the Docker Hub image has version, `latest`, and short-SHA tags.
- Confirm package visibility is public in both registries.
- Confirm Docker pull instructions use the current versioned image.

Suggested checks:

```bash
gh repo view taimoorq/logister --json description,homepageUrl,repositoryTopics,url
gh release view v1.1.0 --json tagName,isLatest,isDraft,isPrerelease,publishedAt,url
gh api /user/packages/container/logister --jq '{name, visibility, html_url}'
gh api /user/packages/container/logister/versions --jq '.[] | {id, tags: .metadata.container.tags, updated_at}'
docker pull ghcr.io/taimoorq/logister:v1.1.0
docker pull docker.io/taimoorq/logister:v1.1.0
```

## Package and SDK Checks

Keep language package surfaces aligned with the app and docs:

- Ruby package: RubyGems page, README, install snippet, supported Rails/Rack notes.
- Python package: PyPI page, README, install snippet, supported framework notes.
- JavaScript package: npm page, README, browser and Node notes.
- .NET packages: NuGet pages once published, README, ASP.NET Core notes.

For each package, verify the description says it reports errors or events to Logister and links back to the public docs.

## Release Cadence

For every public release:

1. Update the changelog and versioned image references.
2. Deploy the app and docs.
3. Run the release checklist.
4. Resubmit sitemaps if public docs changed substantially.
5. Review search, AI crawler, GitHub, GHCR, Docker Hub, and package signals after 24 hours and again after 7 days.
6. Add any positioning or documentation gaps back to the next SEO and LLM discovery plan pass.
