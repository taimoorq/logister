const googleTagIdMeta = document.querySelector('meta[name="logister-google-tag-id"]')
const googleTagId = googleTagIdMeta && googleTagIdMeta.content ? googleTagIdMeta.content.trim() : null

if (googleTagId) {
  let initialized = false
  let lastPath = null

  const analyticsScriptSelector = 'script[src*="googletagmanager.com/gtag/js"]'

  function analyticsScriptActive() {
    const scripts = Array.from(document.querySelectorAll(analyticsScriptSelector))
    return scripts.some(script => (script.type || "").toLowerCase() !== "text/plain")
  }

  function ensureBootstrap() {
    window.dataLayer = window.dataLayer || []
    window.gtag = window.gtag || function gtag() {
      window.dataLayer.push(arguments)
    }
  }

  function trackPageView() {
    if (!analyticsScriptActive()) return

    ensureBootstrap()

    if (!initialized) {
      window.gtag("js", new Date())
      initialized = true
    }

    const path = `${window.location.pathname}${window.location.search}`
    if (path === lastPath) return

    lastPath = path
    window.gtag("config", googleTagId, { page_path: path })
  }

  function bindScriptLoadListeners() {
    document.querySelectorAll(analyticsScriptSelector).forEach(script => {
      if (script.dataset.logisterGaBound === "1") return
      script.dataset.logisterGaBound = "1"
      script.addEventListener("load", trackPageView, { once: true })
    })
  }

  const observer = new MutationObserver(() => {
    bindScriptLoadListeners()
    trackPageView()
  })

  observer.observe(document.head, { childList: true, subtree: true })
  bindScriptLoadListeners()

  document.addEventListener("turbo:load", trackPageView)
  window.addEventListener("load", trackPageView)

  // Catch consent being accepted after initial page load.
  let retries = 0
  const timer = window.setInterval(() => {
    retries += 1
    bindScriptLoadListeners()
    trackPageView()

    if (initialized || retries >= 60) window.clearInterval(timer)
  }, 1000)
}
