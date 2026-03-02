import { Controller } from "@hotwired/stimulus"

// Toggles the mobile nav panel (hamburger menu). Keeps one source of truth for nav JS.
export default class extends Controller {
  static targets = ["toggle", "panel", "iconOpen", "iconClose"]

  connect() {
    this.boundClose = this.closeOnClickOutside.bind(this)
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
    this.boundCloseOnNavLink = this.closeOnNavLink.bind(this)
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
    if (event.target.closest?.(".nav-link")) this.close()
  }
}
