import { Controller } from "@hotwired/stimulus"

// Formats all <time datetime="..." data-local-time> in the document in the user's local timezone.
// Re-run through declarative Turbo actions in the layout so dynamic content is formatted.
export default class extends Controller {
  connect() {
    this.formatAll()
  }

  formatAll() {
    document.querySelectorAll("time[datetime][data-local-time]").forEach((el) => this.formatElement(el))
  }

  formatElement(el) {
    const dt = new Date(el.getAttribute("datetime"))
    if (Number.isNaN(dt.getTime())) return

    const format = el.dataset.format || "short"
    const options = this.optionsFor(format)
    const formatted = new Intl.DateTimeFormat(undefined, options).format(dt)
    el.textContent = formatted
  }

  optionsFor(format) {
    switch (format) {
      case "date_only":
        return { dateStyle: "medium" }
      case "long":
        return { dateStyle: "medium", timeStyle: "long" }
      default:
        return { dateStyle: "medium", timeStyle: "short" }
    }
  }
}
