import { Controller } from "@hotwired/stimulus"

const TOUR_COMPLETE_STORAGE_KEY = "tg_tours_complete"

export default class extends Controller {
  static values = {
    group: String,
    autoOnInteraction: { type: Boolean, default: true }
  }

  connect() {
    this.autoStarted = false
  }

  disconnect() {
    this.closeTour()
  }

  start(event) {
    event?.preventDefault()
    event?.stopPropagation()
    this.startTour({ force: true })
  }

  startForNewUser(event) {
    if (!this.autoOnInteractionValue || this.autoStarted || this.tourCompleted() || this.ignoredInteraction(event)) return

    this.autoStarted = true
    window.requestAnimationFrame(() => this.startTour())
  }

  beforeCache() {
    this.closeTour()
  }

  startTour({ force = false } = {}) {
    if (!this.groupValue || (!force && this.tourCompleted()) || !this.hasTourSteps()) return

    const client = this.tourClient()
    if (!client || client.isVisible) return

    client.start(this.groupValue).catch((error) => {
      if (window.console) console.warn("Unable to start product tour", error)
    })
  }

  tourClient() {
    if (this.client) return this.client

    const TourGuideClient = window.tourguide?.TourGuideClient
    if (!TourGuideClient) return null

    this.client = new TourGuideClient({
      debug: false,
      completeOnFinish: true,
      targetPadding: 18,
      dialogMaxWidth: 360,
      exitOnClickOutside: true,
      nextLabel: "Next",
      prevLabel: "Back",
      finishLabel: "Done"
    })

    return this.client
  }

  closeTour() {
    const client = this.client
    this.client = null

    if (client?.isVisible) {
      client.exit().catch((error) => {
        if (window.console) console.warn("Unable to close product tour", error)
      })
    }

    this.removeTourArtifacts()
  }

  removeTourArtifacts() {
    document.body.classList.remove("tg-no-interaction")
    document.querySelectorAll(".tg-dialog, .tg-backdrop").forEach((element) => element.remove())
  }

  hasTourSteps() {
    return Array.from(document.querySelectorAll("[data-tg-tour]")).some((element) => {
      return element.dataset.tgGroup === this.groupValue
    })
  }

  tourCompleted() {
    try {
      const completedTours = window.localStorage.getItem(TOUR_COMPLETE_STORAGE_KEY) || ""
      return completedTours.split(",").includes(this.groupValue)
    } catch (_error) {
      return false
    }
  }

  ignoredInteraction(event) {
    const target = event.target
    if (!(target instanceof Element)) return true

    return Boolean(target.closest("[data-tour-ignore], .tg-dialog, .tg-backdrop, a[href]"))
  }
}
