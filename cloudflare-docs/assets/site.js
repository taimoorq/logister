function loadDocsAnalytics() {
  const config = window.LOGISTER_DOCS_ANALYTICS || {};
  const googleTagId = typeof config.googleTagId === "string" ? config.googleTagId.trim() : "";
  const cloudflareToken = typeof config.cloudflareWebAnalyticsToken === "string" ? config.cloudflareWebAnalyticsToken.trim() : "";
  const doNotTrack = navigator.doNotTrack === "1" || window.doNotTrack === "1" || navigator.msDoNotTrack === "1";

  if (doNotTrack) return;

  if (googleTagId && !document.querySelector('script[src*="googletagmanager.com/gtag/js"]')) {
    const script = document.createElement("script");
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(googleTagId)}`;
    document.head.appendChild(script);

    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function gtag() {
      window.dataLayer.push(arguments);
    };

    window.gtag("js", new Date());
    window.gtag("config", googleTagId, {
      anonymize_ip: true,
      page_path: window.location.pathname + window.location.search
    });
  }

  if (cloudflareToken && !document.querySelector('script[src*="static.cloudflareinsights.com/beacon.min.js"]')) {
    const script = document.createElement("script");
    script.defer = true;
    script.src = "https://static.cloudflareinsights.com/beacon.min.js";
    script.setAttribute("data-cf-beacon", JSON.stringify({ token: cloudflareToken }));
    document.head.appendChild(script);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  loadDocsAnalytics();

  const navToggle = document.querySelector("[data-nav-toggle]");
  const navPanel = document.querySelector("[data-nav-panel]");

  if (navToggle && navPanel) {
    navToggle.addEventListener("click", () => {
      const expanded = navToggle.getAttribute("aria-expanded") === "true";
      navToggle.setAttribute("aria-expanded", String(!expanded));
      navPanel.classList.toggle("is-open", !expanded);
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
