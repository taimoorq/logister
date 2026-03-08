import { Controller } from "@hotwired/stimulus"

// Toggles the mobile nav panel (hamburger menu). Keeps one source of truth for nav JS.
export default class extends Controller {
  static get targets() {
    return ["toggle", "panel", "iconOpen", "iconClose"]
  }

  connect() {
    this.element.dataset.navConnected = "1"
    this.boundClose = this.closeOnClickOutside.bind(this)
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
    this.boundCloseOnNavLink = this.closeOnNavLink.bind(this)
  }

  disconnect() {
    delete this.element.dataset.navConnected
    document.removeEventListener("click", this.boundClose)
    document.removeEventListener("keydown", this.boundCloseOnEscape)
    if (this.hasPanelTarget) this.panelTarget.removeEventListener("click", this.boundCloseOnNavLink)
  }

  toggle(event) {
    event.stopPropagation()
    this.isOpen() ? this.close() : this.open()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "true")
    if (this.hasIconOpenTarget) this.iconOpenTarget.classList.add("hidden")
    if (this.hasIconCloseTarget) this.iconCloseTarget.classList.remove("hidden")
    document.addEventListener("click", this.boundClose)
    document.addEventListener("keydown", this.boundCloseOnEscape)
    if (this.hasPanelTarget) this.panelTarget.addEventListener("click", this.boundCloseOnNavLink)
  }

  close() {
    if (this.hasPanelTarget) this.panelTarget.classList.add("hidden")
    this.closeOpenMenus()
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "false")
    if (this.hasIconOpenTarget) this.iconOpenTarget.classList.remove("hidden")
    if (this.hasIconCloseTarget) this.iconCloseTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundClose)
    document.removeEventListener("keydown", this.boundCloseOnEscape)
    if (this.hasPanelTarget) this.panelTarget.removeEventListener("click", this.boundCloseOnNavLink)
  }

  isOpen() {
    return this.hasPanelTarget && !this.panelTarget.classList.contains("hidden")
  }

  closeOnClickOutside(event) {
    if (this.isOpen() && this.hasPanelTarget && this.hasToggleTarget &&
        !this.panelTarget.contains(event.target) && !this.toggleTarget.contains(event.target)) {
      this.close()
    }
  }

  closeOnEscape(event) {
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
}
