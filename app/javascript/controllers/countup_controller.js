import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static get values() {
    return {
      number: Number,
      duration: { type: Number, default: 1300 },
      decimals: { type: Number, default: 0 },
      suffix: { type: String, default: "" },
      prefix: { type: String, default: "" }
    }
  }

  connect() {
    if (!this.hasNumberValue) return

    // Keep above-the-fold metrics stable to avoid load-time layout shift.
    const rect = this.element.getBoundingClientRect()
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight
    const initiallyVisible = rect.top < viewportHeight * 0.9 && rect.bottom > 0
    if (initiallyVisible) {
      this.render(this.numberValue)
      return
    }

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) {
      this.render(this.numberValue)
      return
    }

    this.observer = new IntersectionObserver(
      entries => {
        entries.forEach(entry => {
          if (!entry.isIntersecting || this.started) return
          this.started = true
          this.start()
          this.observer.disconnect()
        })
      },
      { threshold: 0.4 }
    )

    this.observer.observe(this.element)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  start() {
    const startTime = performance.now()
    const duration = Math.max(this.durationValue, 300)

    const tick = now => {
      const elapsed = Math.min((now - startTime) / duration, 1)
      const eased = 1 - Math.pow(1 - elapsed, 3)
      this.render(this.numberValue * eased)

      if (elapsed < 1) {
        this.frame = requestAnimationFrame(tick)
      }
    }

    this.frame = requestAnimationFrame(tick)
  }

  render(value) {
    const formatted = Number(value).toLocaleString(undefined, {
      minimumFractionDigits: this.decimalsValue,
      maximumFractionDigits: this.decimalsValue
    })

    this.element.textContent = `${this.prefixValue}${formatted}${this.suffixValue}`
  }
}
