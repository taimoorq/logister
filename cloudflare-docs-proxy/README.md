# Cloudflare Docs Proxy

This Worker owns the public `https://logister.org/docs` route and proxies it to the Cloudflare Pages docs origin in `cloudflare-docs/`. It also redirects old `https://docs.logister.org` URLs to the matching `https://logister.org/docs` URL with `301 Moved Permanently`.

## Configuration

- `DOCS_MOUNT_PATH` is the public mount path. The Logister deployment uses `/docs`.
- `DOCS_PAGES_ORIGIN` is the Pages origin URL. Update `wrangler.toml` if your Pages project does not use `https://logister-docs.pages.dev`.
- `OLD_DOCS_HOSTS` is a comma-separated list of legacy docs hosts that should redirect to the public docs URL.
- `PUBLIC_DOCS_ORIGIN` is the public origin for redirected legacy docs URLs. The Logister deployment uses `https://logister.org`.

The Worker strips the public mount path before fetching Pages. For example:

- `/docs/` fetches `/`
- `/docs/getting-started/` fetches `/getting-started/`
- `/docs/pagefind/pagefind-ui.js` fetches `/pagefind/pagefind-ui.js`

Legacy host redirects preserve path and query strings:

- `https://docs.logister.org/` redirects to `https://logister.org/docs/`
- `https://docs.logister.org/getting-started/?q=api` redirects to `https://logister.org/docs/getting-started/?q=api`
- `https://docs.logister.org/docs/getting-started/` redirects to `https://logister.org/docs/getting-started/`

## Deploy

```bash
wrangler deploy --config cloudflare-docs-proxy/wrangler.toml
```

Build the docs with `LOGISTER_DOCS_URL=https://logister.org/docs` before deploying the Pages origin so links, metadata, sitemap, robots, and Pagefind results point at the public route.
