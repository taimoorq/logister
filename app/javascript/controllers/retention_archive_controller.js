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
    this.guardPanelTarget.classList.toggle("opacity-50", !exportsEnabled)
    this.guardHintTarget.hidden = exportsEnabled
  }
}
