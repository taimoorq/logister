import { Controller } from "@hotwired/stimulus"

// Toggles the mobile nav panel (hamburger menu). Keeps one source of truth for nav JS.
export default class extends Controller {
  static get targets() {
    return ["toggle", "panel", "iconOpen", "iconClose"]
  }

  connect() {
    this.mobileOpen = false
    this.boundSyncForViewport = this.syncForViewport.bind(this)
    window.addEventListener("resize", this.boundSyncForViewport)
    this.syncForViewport()
  }

  disconnect() {
    window.removeEventListener("resize", this.boundSyncForViewport)
  }

  toggle(event) {
    event.stopPropagation()
    this.isOpen() ? this.close() : this.open()
  }

  open() {
    this.mobileOpen = true
    this.applyState(true)
  }

  close() {
    this.closeOpenMenus()
    this.mobileOpen = false
    this.applyState(false)
  }

  isOpen() {
    return this.element.dataset.navState === "open"
  }

  closeOnClickOutside(event) {
    if (this.isDesktop()) return
    if (this.isOpen() && this.hasPanelTarget && this.hasToggleTarget &&
        !this.panelTarget.contains(event.target) && !this.toggleTarget.contains(event.target)) {
      this.close()
    }
  }

  closeOnEscape(event) {
    if (this.isDesktop()) return
    if (event.key === "Escape" && this.isOpen()) this.close()
  }

  closeOnNavLink(event) {
    const target = event && event.target
    if (target && typeof target.closest === "function" && target.closest(".nav-link")) this.close()
  }

  closeOpenMenus() {
    if (!this.hasPanelTarget) return

    this.panelTarget.querySelectorAll("details[open]").forEach((el) => {
      el.removeAttribute("open")
    })
  }

  applyState(open) {
    const panelVisible = this.isDesktop() || open
    this.element.dataset.navState = panelVisible ? "open" : "closed"

    if (this.hasPanelTarget) {
      this.panelTarget.classList.toggle("hidden", !panelVisible)
      this.panelTarget.setAttribute("aria-hidden", panelVisible ? "false" : "true")
      this.panelTarget.dataset.state = panelVisible ? "open" : "closed"
    }

    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", !this.isDesktop() && open ? "true" : "false")
    }
  }

  syncForViewport() {
    this.applyState(this.mobileOpen)
  }

  isDesktop() {
    return window.matchMedia("(min-width: 768px)").matches
  }
}
