import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "custom", "input"]

  connect() {
    this.update()
  }

  update() {
    const custom = this.selectTarget.value === "__custom__"
    this.customTarget.hidden = !custom
    this.inputTarget.disabled = !custom
    this.inputTarget.required = custom
  }
}
