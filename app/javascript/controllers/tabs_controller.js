import { Controller } from "@hotwired/stimulus"

// Drives tabbed UI — buttons toggle between panels without any page navigation.
// Usage:
//   data-controller="tabs"
//   data-tabs-target="tab"    data-action="click->tabs#show"  data-panel="panel-id"
//   data-tabs-target="panel"  id="panel-id"
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Ensure the first active tab/panel pair is correct on initial load
    this.syncActive()
  }

  show(event) {
    const panelId = event.currentTarget.dataset.panel
    this.tabTargets.forEach(tab => tab.classList.toggle("is-active", tab.dataset.panel === panelId))
    this.panelTargets.forEach(panel => panel.classList.toggle("is-hidden", panel.id !== panelId))
  }

  // Called after a Turbo Frame replaces content so tabs stay in sync
  syncActive() {
    const activeTab = this.tabTargets.find(t => t.classList.contains("is-active"))
    if (!activeTab) return
    const panelId = activeTab.dataset.panel
    this.panelTargets.forEach(panel => panel.classList.toggle("is-hidden", panel.id !== panelId))
  }
}
