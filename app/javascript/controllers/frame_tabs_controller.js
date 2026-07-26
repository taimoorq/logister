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
    this.previousTabId = null
    this.syncStateFromMarkup()
    this.element.setAttribute("aria-busy", "false")
  }

  activate(event) {
    const tab = event.currentTarget
    if (!(tab instanceof HTMLElement)) return

    const previous = this.tabTargets.find((candidate) => candidate.getAttribute("aria-selected") === "true")
    this.previousTabId = previous ? previous.id : null
    this.applyActiveState(tab)
    if (this.hasTurboFrameValue) this.element.setAttribute("aria-busy", "true")
  }

  navigate(event) {
    const currentIndex = this.tabTargets.indexOf(event.currentTarget)
    if (currentIndex < 0) return

    let nextIndex
    if (["ArrowRight", "ArrowDown"].includes(event.key)) nextIndex = (currentIndex + 1) % this.tabTargets.length
    if (["ArrowLeft", "ArrowUp"].includes(event.key)) nextIndex = (currentIndex - 1 + this.tabTargets.length) % this.tabTargets.length
    if (event.key === "Home") nextIndex = 0
    if (event.key === "End") nextIndex = this.tabTargets.length - 1
    if (nextIndex === undefined) return

    event.preventDefault()
    this.tabTargets[nextIndex].focus()
  }

  onBeforeFetch(event) {
    if (!this.matchesManagedFrame(event.target)) return

    this.element.setAttribute("aria-busy", "true")
  }

  onFrameLoad(event) {
    if (!this.matchesManagedFrame(event.target)) return

    this.element.setAttribute("aria-busy", "false")
    this.previousTabId = null
  }

  onFetchError(event) {
    if (!this.matchesManagedFrame(event.target)) return

    const previous = this.previousTabId ? document.getElementById(this.previousTabId) : null
    if (previous) this.applyActiveState(previous)
    this.previousTabId = null
    this.element.setAttribute("aria-busy", "false")
  }

  syncStateFromMarkup() {
    const activeTab = this.tabTargets.find((tab) => {
      return tab.getAttribute("aria-current") === "page" ||
        tab.getAttribute("aria-selected") === "true" ||
        tab.dataset.state === "active" ||
        tab.classList.contains("is-active")
    }) || this.tabTargets[0]
    if (!activeTab) return

    this.applyActiveState(activeTab)
    this.panelTargets.forEach((panel) => {
      const isVisible = !panel.hidden
      panel.setAttribute("aria-hidden", isVisible ? "false" : "true")
      panel.dataset.state = isVisible ? "active" : "inactive"
    })
  }

  applyActiveState(activeTab) {
    const activePanelId = activeTab.getAttribute("aria-controls")

    this.tabTargets.forEach((tab) => {
      const isActive = tab === activeTab
      tab.setAttribute("aria-selected", isActive ? "true" : "false")
      tab.setAttribute("tabindex", isActive ? "0" : "-1")
      tab.dataset.state = isActive ? "active" : "inactive"
      if (isActive) {
        tab.setAttribute("aria-current", "page")
      } else {
        tab.removeAttribute("aria-current")
      }
    })

    this.panelTargets.forEach((panel) => {
      const isActive = panel.id === activePanelId
      panel.hidden = !isActive
      panel.setAttribute("aria-hidden", isActive ? "false" : "true")
      panel.dataset.state = isActive ? "active" : "inactive"
    })
  }

  matchesManagedFrame(target) {
    if (!(target instanceof HTMLElement) || !this.hasTurboFrameValue) return false

    return target.id === this.turboFrameValue
  }
}
