import { Controller } from "@hotwired/stimulus"

// Drives tabbed UI — buttons toggle between panels without any page navigation.
// Usage:
//   data-controller="tabs"
//   data-tabs-target="tab"    data-action="click->tabs#show"  data-panel="panel-id"
//   data-tabs-target="panel"  id="panel-id"
export default class extends Controller {
  static get targets() {
    return ["tab", "panel"]
  }

  connect() {
    this.boundDelegatedClick = this.handleDelegatedClick.bind(this)
    this.element.addEventListener("click", this.boundDelegatedClick)
    this.decorateTabs()
    this.syncActive()
  }

  disconnect() {
    this.element.removeEventListener("click", this.boundDelegatedClick)
  }

  show(event) {
    event.preventDefault()
    const tab = event.currentTarget
    const panelId = tab && tab.dataset ? tab.dataset.panel : null
    if (!panelId) return
    this.activate(panelId)
  }

  handleDelegatedClick(event) {
    const target = event.target
    if (!target || typeof target.closest !== "function") return

    const tab = target.closest("[data-tabs-target='tab'][data-panel]")
    if (!tab || !this.element.contains(tab)) return

    event.preventDefault()
    const panelId = tab.dataset ? tab.dataset.panel : null
    if (!panelId) return
    this.activate(panelId)
  }

  // Called after a Turbo Frame replaces content so tabs stay in sync
  syncActive() {
    const activeTab = this.tabTargets.find((tab) => {
      return tab.getAttribute("aria-selected") === "true" ||
        tab.dataset.state === "active" ||
        tab.classList.contains("is-active")
    }) || this.tabTargets[0]
    if (!activeTab) return
    const panelId = activeTab.dataset.panel
    this.activate(panelId)
  }

  activate(panelId) {
    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.panel === panelId
      tab.setAttribute("aria-selected", isActive ? "true" : "false")
      tab.setAttribute("tabindex", isActive ? "0" : "-1")
      tab.dataset.state = isActive ? "active" : "inactive"
    })

    this.panelTargets.forEach(panel => {
      const isActive = panel.id === panelId
      panel.hidden = !isActive
      panel.setAttribute("aria-hidden", isActive ? "false" : "true")
      panel.dataset.state = isActive ? "active" : "inactive"
    })
  }

  decorateTabs() {
    this.tabTargets.forEach(tab => {
      const panelId = tab.dataset ? tab.dataset.panel : null
      if (!panelId) return
      tab.setAttribute("aria-controls", panelId)
      if (!tab.hasAttribute("type")) tab.setAttribute("type", "button")
    })

    this.panelTargets.forEach(panel => {
      panel.setAttribute("role", "tabpanel")
    })
  }
}
