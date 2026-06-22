import { Controller } from "@hotwired/stimulus"

const LABELS = {
  error: "Errors",
  log: "Logs",
  metric: "Metrics",
  transaction: "Transactions",
  check_in: "Check-ins"
}

export default class extends Controller {
  static targets = ["filter", "item", "empty", "title", "subtitle"]
  static values = {
    active: { type: String, default: "error" }
  }

  connect() {
    this.applyFilter(this.activeValue)
  }

  filter(event) {
    event.preventDefault()
    this.transition(() => this.applyFilter(event.currentTarget.dataset.eventType || "error"))
  }

  applyFilter(eventType) {
    this.activeValue = eventType
    let visibleCount = 0

    this.filterTargets.forEach((filter) => {
      const active = filter.dataset.eventType === eventType
      filter.setAttribute("aria-pressed", active ? "true" : "false")
      filter.dataset.state = active ? "active" : "inactive"
    })

    this.itemTargets.forEach((item) => {
      const visible = item.dataset.eventType === eventType
      item.hidden = !visible
      if (visible) visibleCount += 1
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visibleCount > 0
    }

    this.updateHeading(eventType, visibleCount)
  }

  updateHeading(eventType, visibleCount) {
    const label = LABELS[eventType] || eventType

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = eventType === "error" ? "Needs attention" : `Recent ${label.toLowerCase()}`
    }

    if (!this.hasSubtitleTarget) return

    if (eventType === "error") {
      this.subtitleTarget.textContent = `${visibleCount} open ${visibleCount === 1 ? "error group" : "error groups"} sorted by latest activity`
    } else {
      this.subtitleTarget.textContent = `${visibleCount} recent ${label.toLowerCase()} ${visibleCount === 1 ? "event" : "events"} across apps`
    }
  }

  transition(callback) {
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reduceMotion || typeof document.startViewTransition !== "function") {
      callback()
      return
    }

    document.startViewTransition(callback)
  }
}
