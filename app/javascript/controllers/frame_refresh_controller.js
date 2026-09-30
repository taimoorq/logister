import { Controller } from "@hotwired/stimulus"

// Re-requests the surrounding Turbo Frame until the server stops rendering this
// element (the evidence arrived, or the attempts ran out). Each response replaces
// the frame's content, so a finished check simply has no controller left to run.
//
// If a request fails, the frame keeps its last good status and the check is
// retried a little later, so a brief server or network problem does not leave
// the panel frozen on "Waiting".
export default class extends Controller {
  static values = {
    url: String,
    attempt: Number,
    max: Number,
    interval: { type: Number, default: 4000 }
  }

  static MAX_RETRY_INTERVAL = 30000

  connect() {
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  schedule() {
    clearTimeout(this.timer)
    if (this.attemptValue >= this.maxValue) return

    this.timer = setTimeout(() => this.refresh(), this.intervalValue)
  }

  refresh() {
    // Do not poll a hidden tab; check again shortly.
    if (document.hidden) return this.schedule()

    const frame = this.frame
    if (!frame) return

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("attempt", this.attemptValue + 1)
    frame.src = url.toString()
  }

  // Wired to turbo:before-fetch-response and turbo:fetch-request-error on the
  // document, so Stimulus removes the listeners when this controller disconnects.
  // A response with any non-2xx status (even an empty one, which Turbo would
  // otherwise report as a missing frame) is treated as a failed check.
  responded(event) {
    if (event.target !== this.frame || event.detail.fetchResponse.succeeded) return

    this.failed(event)
  }

  failed(event) {
    if (event.target !== this.frame) return

    event.preventDefault() // keep the last good status instead of an error message
    this.attemptValue += 1
    this.intervalValue = Math.min(this.intervalValue * 2, this.constructor.MAX_RETRY_INTERVAL)
    this.schedule()
  }

  get frame() {
    return this.element.closest("turbo-frame")
  }
}
