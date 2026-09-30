import { Controller } from "@hotwired/stimulus"

// Dismisses a native <details> menu: on a click outside it, on Escape (returning
// focus to its summary), and before Turbo caches the page, so a snapshot never
// restores an open menu. The <details> element still works without JavaScript.
export default class extends Controller {
  static targets = ["details"]

  closeOutside(event) {
    if (!this.isOpen || this.element.contains(event.target)) return

    this.close()
  }

  closeOnEscape(event) {
    if (!this.isOpen) return

    this.close()
    this.summary?.focus()
    event.stopPropagation()
  }

  close() {
    if (this.hasDetailsTarget) this.detailsTarget.open = false
  }

  get isOpen() {
    return this.hasDetailsTarget && this.detailsTarget.open
  }

  get summary() {
    return this.detailsTarget.querySelector("summary")
  }
}
