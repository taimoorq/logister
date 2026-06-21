const DOCS_BASE_PATH = docsBasePath();

function docsBasePath() {
  const script = document.currentScript || document.querySelector('script[src$="/assets/site.js"]');
  if (!script) return "";

  const scriptUrl = new URL(script.src, window.location.href);
  const assetPath = "/assets/site.js";
  if (!scriptUrl.pathname.endsWith(assetPath)) return "";

  return scriptUrl.pathname.slice(0, -assetPath.length).replace(/\/$/, "");
}

function docsPath(path) {
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  return `${DOCS_BASE_PATH}${normalizedPath}`;
}

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

function loadDocsSearch() {
  const topbar = document.querySelector(".topbar-inner");
  if (!topbar || document.querySelector("[data-logister-docs-search]")) return;

  const search = document.createElement("div");
  search.id = "docs-search";
  search.className = "docs-search";
  search.setAttribute("data-logister-docs-search", "true");
  search.setAttribute("data-pagefind-ignore", "true");

  const navToggle = topbar.querySelector("[data-nav-toggle]");
  topbar.insertBefore(search, navToggle || topbar.querySelector("[data-nav-panel]"));

  if (!document.querySelector('[data-logister-docs-search-style="pagefind"]')) {
    const stylesheet = document.createElement("link");
    stylesheet.rel = "stylesheet";
    stylesheet.href = docsPath("/pagefind/pagefind-ui.css");
    stylesheet.setAttribute("data-logister-docs-search-style", "pagefind");
    document.head.appendChild(stylesheet);
  }

  const script = document.createElement("script");
  script.src = docsPath("/pagefind/pagefind-ui.js");
  script.defer = true;
  script.setAttribute("data-logister-docs-search-script", "pagefind");
  script.addEventListener("load", () => {
    if (!window.PagefindUI) return;

    new window.PagefindUI({
      element: "#docs-search",
      showImages: false,
      showSubResults: true,
      excerptLength: 24,
      translations: {
        placeholder: "Search docs"
      }
    });
  });
  script.addEventListener("error", () => {
    search.remove();
  });
  document.head.appendChild(script);
}

function enhanceSidebarSections(sidebar) {
  const groups = Array.from(sidebar.querySelectorAll(".sidebar-group"));
  const hasActiveGroup = groups.some((group) => Boolean(group.querySelector("a.active")));

  groups.forEach((group, index) => {
    if (group.dataset.sidebarEnhanced === "true") return;

    const label = Array.from(group.children).find((child) => child.classList.contains("sidebar-label"));
    const links = Array.from(group.children).filter((child) => child.tagName === "A");
    if (!label || links.length === 0) return;

    const title = (label.textContent || "Section").trim();
    const panel = document.createElement("div");
    const panelId = `sidebar-section-${index}-${slugifySidebarTitle(title)}`;
    panel.id = panelId;
    panel.className = "sidebar-group-panel";

    while (label.nextSibling) {
      panel.appendChild(label.nextSibling);
    }

    const button = document.createElement("button");
    button.type = "button";
    button.className = "sidebar-section-toggle";
    button.setAttribute("aria-controls", panelId);

    const buttonLabel = document.createElement("span");
    buttonLabel.className = "sidebar-section-label";
    buttonLabel.textContent = title;

    const chevron = document.createElement("span");
    chevron.className = "sidebar-section-chevron";
    chevron.setAttribute("aria-hidden", "true");

    button.append(buttonLabel, chevron);
    group.replaceChild(button, label);
    group.appendChild(panel);
    group.dataset.sidebarEnhanced = "true";

    const storageKey = `logister-docs-sidebar:${window.location.pathname}:${title}`;
    const hasActiveLink = Boolean(panel.querySelector("a.active"));
    const storedState = readSidebarState(storageKey);
    const defaultOpen = hasActiveLink || (!hasActiveGroup && index === 0);
    const isOpen = hasActiveLink || (storedState === null ? defaultOpen : storedState);

    setSidebarSectionState(group, button, panel, isOpen);

    button.addEventListener("click", () => {
      const expanded = button.getAttribute("aria-expanded") === "true";
      const nextOpen = !expanded;
      setSidebarSectionState(group, button, panel, nextOpen);
      writeSidebarState(storageKey, nextOpen);
    });
  });
}

function slugifySidebarTitle(title) {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "") || "section";
}

function setSidebarSectionState(group, button, panel, isOpen) {
  button.setAttribute("aria-expanded", String(isOpen));
  panel.hidden = !isOpen;
  group.classList.toggle("is-open", isOpen);
}

function readSidebarState(key) {
  try {
    const value = window.localStorage.getItem(key);
    if (value === "open") return true;
    if (value === "closed") return false;
  } catch (_error) {
    return null;
  }

  return null;
}

function writeSidebarState(key, isOpen) {
  try {
    window.localStorage.setItem(key, isOpen ? "open" : "closed");
  } catch (_error) {
    return;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  loadDocsAnalytics();
  loadDocsSearch();

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
    enhanceSidebarSections(sidebar);

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
