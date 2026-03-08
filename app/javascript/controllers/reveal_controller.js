import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static get values() {
    return {
      animationClass: { type: String, default: "reveal-up" },
      delay: { type: Number, default: 0 }
    }
  }

  connect() {
    this.element.classList.add(this.animationClassValue)

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) {
      this.element.classList.add("is-visible")
      return
    }

    const rect = this.element.getBoundingClientRect()
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight
    const initiallyVisible = rect.top < viewportHeight * 0.9 && rect.bottom > 0

    // Render above-the-fold content immediately to avoid load-time layout jank.
    if (initiallyVisible) {
      this.element.style.transitionDelay = "0ms"
      this.element.classList.add("is-visible")
      return
    }

    if (this.delayValue > 0) {
      this.element.style.transitionDelay = `${this.delayValue}ms`
    }

    this.observer = new IntersectionObserver(
      entries => {
        entries.forEach(entry => {
          if (!entry.isIntersecting) return

          this.element.classList.add("is-visible")
          this.observer.disconnect()
        })
      },
      { threshold: 0.18 }
    )

    this.observer.observe(this.element)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }
}
