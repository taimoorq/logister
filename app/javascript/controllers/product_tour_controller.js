import { Controller } from "@hotwired/stimulus"

const TOUR_COMPLETE_STORAGE_KEY = "tg_tours_complete"

export default class extends Controller {
  static values = {
    group: String,
    autoOnInteraction: { type: Boolean, default: true }
  }

  connect() {
    this.autoStarted = false
    this.autoStartFrame = null
    this.autoStartTimer = null
    this.handleTourCloseClick = this.handleTourCloseClick.bind(this)
    document.addEventListener("click", this.handleTourCloseClick, true)
    this.startForNewUser()
  }

  disconnect() {
    document.removeEventListener("click", this.handleTourCloseClick, true)
    this.cancelAutoStart()
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
    this.queueAutoStart()
  }

  beforeCache() {
    this.closeTour()
  }

  startTour({ force = false } = {}) {
    if (!this.groupValue || (!force && this.tourCompleted()) || !this.hasTourSteps()) return false

    const client = this.tourClient()
    if (!client || client.isVisible) return false

    client.start(this.groupValue).catch((error) => {
      if (window.console) console.warn("Unable to start product tour", error)
    })

    return true
  }

  queueAutoStart(attempt = 0) {
    this.cancelAutoStart()

    this.autoStartFrame = window.requestAnimationFrame(() => {
      this.autoStartFrame = null
      if (!this.element.isConnected || this.startTour()) return

      if (attempt >= 10 || this.tourCompleted()) {
        this.autoStarted = false
        return
      }

      this.autoStartTimer = window.setTimeout(() => this.queueAutoStart(attempt + 1), 100)
    })
  }

  cancelAutoStart() {
    if (this.autoStartFrame) {
      window.cancelAnimationFrame(this.autoStartFrame)
      this.autoStartFrame = null
    }

    if (this.autoStartTimer) {
      window.clearTimeout(this.autoStartTimer)
      this.autoStartTimer = null
    }
  }

  handleTourCloseClick(event) {
    const target = event.target
    if (!(target instanceof Element) || !target.closest("#tg-dialog-close-btn")) return

    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation()
    this.markTourCompleted()
    this.exitVisibleTour()
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
    this.client.onBeforeExit(() => {
      if (!this.suppressExitCompletion) this.markTourCompleted()
    })

    return this.client
  }

  closeTour() {
    const client = this.client
    this.client = null

    if (client?.isVisible) {
      this.suppressExitCompletion = true
      this.exitVisibleTour(client).finally(() => {
        this.suppressExitCompletion = false
      })
    }

    this.removeTourArtifacts()
  }

  exitVisibleTour(client = this.client) {
    return client?.exit().catch((error) => {
      if (window.console) console.warn("Unable to close product tour", error)
    }) || Promise.resolve()
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

  markTourCompleted() {
    try {
      const completedTours = window.localStorage.getItem(TOUR_COMPLETE_STORAGE_KEY) || ""
      const tourGroups = completedTours.split(",").filter(Boolean)
      if (tourGroups.includes(this.groupValue)) return

      tourGroups.push(this.groupValue)
      window.localStorage.setItem(TOUR_COMPLETE_STORAGE_KEY, tourGroups.join(","))
    } catch (_error) {
      return
    }
  }

  ignoredInteraction(event) {
    if (!event) return false

    const target = event.target
    if (!(target instanceof Element)) return true

    return Boolean(target.closest("[data-tour-ignore], .tg-dialog, .tg-backdrop, a[href]"))
  }
}
