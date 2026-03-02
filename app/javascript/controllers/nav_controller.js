import { Controller } from "@hotwired/stimulus"

// Toggles mobile nav menu. On desktop (md+) the menu is always visible; on mobile it's a hamburger dropdown.
export default class extends Controller {
  static targets = [ "panel", "button", "iconOpen", "iconClose" ]

  connect() {
    this.closeOnEscape = this.closeOnEscape.bind(this)
    this.closeOnClickOutside = this.closeOnClickOutside.bind(this)
  }

  toggle() {
    this.isOpen() ? this.close() : this.open()
  }

  open() {
    document.addEventListener("keydown", this.closeOnEscape)
    document.addEventListener("click", this.closeOnClickOutside)
    this.panelTarget.classList.remove("hidden")
    this.buttonTarget?.setAttribute("aria-expanded", "true")
    this.iconOpenTarget?.classList.add("hidden")
    this.iconCloseTarget?.classList.remove("hidden")
  }

  close() {
    document.removeEventListener("keydown", this.closeOnEscape)
    document.removeEventListener("click", this.closeOnClickOutside)
    this.panelTarget.classList.add("hidden")
    this.buttonTarget?.setAttribute("aria-expanded", "false")
    this.iconOpenTarget?.classList.remove("hidden")
    this.iconCloseTarget?.classList.add("hidden")
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }

  closeOnClickOutside(event) {
    if (this.element.contains(event.target)) return
    this.close()
  }

  isOpen() {
    return this.panelTarget && !this.panelTarget.classList.contains("hidden")
  }
}
