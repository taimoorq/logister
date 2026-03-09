import { Controller } from "@hotwired/stimulus"

// Lightweight carousel for marketing screenshots.
export default class extends Controller {
  static get targets() {
    return ["track", "slide", "dot"]
  }

  connect() {
    this.index = 0
    this.count = this.slideTargets.length
    if (this.hasTrackTarget && this.count > 0) {
      this.trackTarget.style.width = `${this.count * 100}%`
    }
    this.update()
  }

  prev(event) {
    event.preventDefault()
    if (this.count === 0) return
    this.index = (this.index - 1 + this.count) % this.count
    this.update()
  }

  next(event) {
    event.preventDefault()
    if (this.count === 0) return
    this.index = (this.index + 1) % this.count
    this.update()
  }

  go(event) {
    event.preventDefault()
    const value = Number.parseInt(event.currentTarget.dataset.slideIndex || "0", 10)
    if (Number.isNaN(value) || value < 0 || value >= this.count) return
    this.index = value
    this.update()
  }

  update() {
    if (this.hasTrackTarget && this.count > 0) {
      const step = 100 / this.count
      this.trackTarget.style.transform = `translateX(-${this.index * step}%)`
    }

    this.slideTargets.forEach((slide, idx) => {
      slide.setAttribute("aria-hidden", idx === this.index ? "false" : "true")
    })

    this.dotTargets.forEach((dot, idx) => {
      const active = idx === this.index
      dot.classList.toggle("is-active", active)
      dot.setAttribute("aria-current", active ? "true" : "false")
    })
  }
}
