function loadDocsAnalytics() {
  const config = window.LOGISTER_DOCS_ANALYTICS || {};
  const googleTagId = typeof config.googleTagId === "string" ? config.googleTagId.trim() : "";
  const cloudflareToken = typeof config.cloudflareWebAnalyticsToken === "string" ? config.cloudflareWebAnalyticsToken.trim() : "";
  const doNotTrack = navigator.doNotTrack === "1" || window.doNotTrack === "1" || navigator.msDoNotTrack === "1";
  const hasAnalytics = Boolean(googleTagId || cloudflareToken);

  if (doNotTrack) return;

  const proboLoaded = loadDocsCookieBanner(config);
  if (hasAnalytics && !proboLoaded) {
    console.warn("Logister docs analytics disabled because Probo cookie banner configuration is missing.");
    return;
  }

  const analyticsCategory = docsCookieBannerConfig(config).analyticsCategory;

  if (googleTagId && !document.querySelector('[data-logister-docs-analytics="google-loader"]')) {
    const script = createConsentScript(analyticsCategory);
    script.async = true;
    script.setAttribute("data-src", `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(googleTagId)}`);
    script.setAttribute("data-logister-docs-analytics", "google-loader");
    document.head.appendChild(script);

    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function gtag() {
      window.dataLayer.push(arguments);
    };

    const inlineScript = createConsentScript(analyticsCategory);
    inlineScript.setAttribute("data-logister-docs-analytics", "google-config");
    inlineScript.textContent = `
      window.dataLayer = window.dataLayer || [];
      window.gtag = window.gtag || function gtag(){ window.dataLayer.push(arguments); };
      window.gtag("js", new Date());
      window.gtag("config", ${JSON.stringify(googleTagId)}, {
        anonymize_ip: true,
        page_path: window.location.pathname + window.location.search
      });
    `;
    document.head.appendChild(inlineScript);
  }

  if (cloudflareToken && !document.querySelector('[data-logister-docs-analytics="cloudflare"]')) {
    const script = createConsentScript(analyticsCategory);
    script.defer = true;
    script.setAttribute("data-src", "https://static.cloudflareinsights.com/beacon.min.js");
    script.setAttribute("data-cf-beacon", JSON.stringify({ token: cloudflareToken }));
    script.setAttribute("data-logister-docs-analytics", "cloudflare");
    document.head.appendChild(script);
  }
}

function docsCookieBannerConfig(config) {
  const cookieBanner = config.cookieBanner || {};
  return {
    scriptUrl: typeof cookieBanner.scriptUrl === "string" && cookieBanner.scriptUrl.trim()
      ? cookieBanner.scriptUrl.trim()
      : "https://cdn.jsdelivr.net/npm/@probo/cookie-banner/dist/cookie-banner.iife.js",
    bannerId: typeof cookieBanner.bannerId === "string" ? cookieBanner.bannerId.trim() : "",
    baseUrl: typeof cookieBanner.baseUrl === "string" ? cookieBanner.baseUrl.trim() : "",
    position: typeof cookieBanner.position === "string" && cookieBanner.position.trim()
      ? cookieBanner.position.trim()
      : "bottom-left",
    analyticsCategory: typeof cookieBanner.analyticsCategory === "string" && cookieBanner.analyticsCategory.trim()
      ? cookieBanner.analyticsCategory.trim()
      : "analytics"
  };
}

function loadDocsCookieBanner(config) {
  const cookieBanner = docsCookieBannerConfig(config);
  if (!cookieBanner.bannerId || !cookieBanner.baseUrl) return false;
  if (document.querySelector("probo-cookie-banner") || document.querySelector("[data-logister-docs-probo-banner]")) return true;

  const script = document.createElement("script");
  script.src = cookieBanner.scriptUrl;
  script.defer = true;
  script.setAttribute("data-logister-docs-probo-banner", "true");
  script.setAttribute("data-banner-id", cookieBanner.bannerId);
  script.setAttribute("data-base-url", cookieBanner.baseUrl);
  script.setAttribute("data-position", cookieBanner.position);
  document.head.appendChild(script);
  return true;
}

function createConsentScript(category) {
  const script = document.createElement("script");
  script.type = "text/plain";
  script.setAttribute("data-cookie-consent", category);
  return script;
}

document.addEventListener("DOMContentLoaded", () => {
  loadDocsAnalytics();

  const navToggle = document.querySelector("[data-nav-toggle]");
  const navPanel = document.querySelector("[data-nav-panel]");
  const sidebar = document.querySelector(".sidebar");

  if (navToggle && navPanel) {
    navToggle.addEventListener("click", () => {
      const expanded = navToggle.getAttribute("aria-expanded") === "true";
      navToggle.setAttribute("aria-expanded", String(!expanded));
      navPanel.classList.toggle("is-open", !expanded);
    });
  }

  if (sidebar) {
    const sidebarToggle = document.createElement("button");
    sidebarToggle.type = "button";
    sidebarToggle.className = "sidebar-toggle";
    sidebarToggle.setAttribute("aria-expanded", "false");
    sidebarToggle.innerHTML = `
      <span class="sidebar-toggle-label">
        <span class="sidebar-toggle-kicker">Documentation</span>
        <span>Contents</span>
      </span>
      <span class="sidebar-toggle-chevron" aria-hidden="true">▾</span>
    `;

    sidebar.parentNode.insertBefore(sidebarToggle, sidebar);

    sidebarToggle.addEventListener("click", () => {
      const expanded = sidebarToggle.getAttribute("aria-expanded") === "true";
      sidebarToggle.setAttribute("aria-expanded", String(!expanded));
      sidebar.classList.toggle("is-open", !expanded);
    });
  }

  document.querySelectorAll("[data-copy-button]").forEach((button) => {
    button.addEventListener("click", async () => {
      const selector = button.getAttribute("data-copy-target");
      const source = selector ? document.querySelector(selector) : button.closest(".code-block")?.querySelector("code");
      if (!source) return;

      const original = button.textContent;
      try {
        await navigator.clipboard.writeText(source.textContent || "");
        button.textContent = "Copied";
        button.classList.add("is-copied");
      } catch (_error) {
        button.textContent = "Failed";
        button.classList.add("is-failed");
      }

      window.setTimeout(() => {
        button.textContent = original;
        button.classList.remove("is-copied", "is-failed");
      }, 1500);
    });
  });
});
