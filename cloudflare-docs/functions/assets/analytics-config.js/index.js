const DEFAULT_PROBO_SCRIPT_URL = "https://cdn.jsdelivr.net/npm/@probo/cookie-banner/dist/cookie-banner.iife.js";

function envValue(env, name, fallback = null) {
  const value = env[name];
  if (typeof value !== "string") return fallback;

  const trimmed = value.trim();
  return trimmed || fallback;
}

export function onRequestGet({ env }) {
  const config = {
    googleTagId: envValue(env, "DOCS_GOOGLE_TAG_ID"),
    cloudflareWebAnalyticsToken: envValue(env, "DOCS_CLOUDFLARE_WEB_ANALYTICS_TOKEN"),
    cookieBanner: {
      scriptUrl: envValue(env, "DOCS_PROBO_COOKIE_BANNER_SCRIPT_URL", DEFAULT_PROBO_SCRIPT_URL),
      bannerId: envValue(env, "DOCS_PROBO_COOKIE_BANNER_ID"),
      baseUrl: envValue(env, "DOCS_PROBO_COOKIE_BANNER_BASE_URL"),
      position: envValue(env, "DOCS_PROBO_COOKIE_BANNER_POSITION", "bottom-left"),
      analyticsCategory: envValue(env, "DOCS_ANALYTICS_COOKIE_CATEGORY", "analytics")
    }
  };

  return new Response(`window.LOGISTER_DOCS_ANALYTICS = ${JSON.stringify(config)};\n`, {
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/javascript; charset=utf-8"
    }
  });
}
