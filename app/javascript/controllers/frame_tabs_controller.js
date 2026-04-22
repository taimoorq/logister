import { Controller } from "@hotwired/stimulus"

// Drives server-rendered tab links that reload a Turbo Frame.
// The server remains the source of truth for tab content, while we expose
// active/pending state immediately through attributes the CSS can react to.
export default class extends Controller {
  static values = {
    turboFrame: String
  }

  static get targets() {
    return ["panel", "tab"]
  }

  connect() {
    this.syncStateFromMarkup()
    this.element.setAttribute("aria-busy", "false")
  }

  activate(event) {
    const tab = event.currentTarget
    if (!(tab instanceof HTMLElement)) return

    this.applyActiveState(tab)
    if (this.hasTurboFrameValue) this.element.setAttribute("aria-busy", "true")
  }

  onBeforeFetch(event) {
    if (!this.matchesManagedFrame(event.target)) return

    this.element.setAttribute("aria-busy", "true")
  }

  onFrameLoad(event) {
    if (!this.matchesManagedFrame(event.target)) return

    this.element.setAttribute("aria-busy", "false")
  }

  syncStateFromMarkup() {
    const activeTab = this.tabTargets.find((tab) => tab.classList.contains("is-active")) || this.tabTargets[0]
    if (!activeTab) return

    this.applyActiveState(activeTab)
    this.panelTargets.forEach((panel) => {
      const isVisible = !panel.classList.contains("is-hidden") && !panel.hidden
      panel.setAttribute("aria-hidden", isVisible ? "false" : "true")
    })
  }

  applyActiveState(activeTab) {
    const activePanelId = activeTab.getAttribute("aria-controls")

    this.tabTargets.forEach((tab) => {
      const isActive = tab === activeTab
      tab.classList.toggle("is-active", isActive)
      tab.setAttribute("aria-selected", isActive ? "true" : "false")
      tab.setAttribute("tabindex", isActive ? "0" : "-1")
      if (isActive) {
        tab.setAttribute("aria-current", "page")
      } else {
        tab.removeAttribute("aria-current")
      }
    })

    this.panelTargets.forEach((panel) => {
      const isActive = panel.id === activePanelId
      panel.classList.toggle("is-hidden", !isActive)
      panel.hidden = !isActive
      panel.setAttribute("aria-hidden", isActive ? "false" : "true")
    })
  }

  matchesManagedFrame(target) {
    if (!(target instanceof HTMLElement) || !this.hasTurboFrameValue) return false

    return target.id === this.turboFrameValue
  }
}
