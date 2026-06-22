import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static get targets() {
    return ["exports", "guard", "guardPanel", "guardHint"]
  }

  connect() {
    this.sync()
  }

  sync() {
    const exportsEnabled = this.exportsTarget.checked

    if (!exportsEnabled) {
      this.guardTarget.checked = false
    }

    this.guardTarget.disabled = !exportsEnabled
    this.guardPanelTarget.dataset.state = exportsEnabled ? "enabled" : "disabled"
    this.guardPanelTarget.setAttribute("aria-disabled", exportsEnabled ? "false" : "true")
    this.guardHintTarget.hidden = exportsEnabled
  }
}
