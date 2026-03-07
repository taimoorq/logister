import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    animationClass: { type: String, default: "reveal-up" },
    delay: { type: Number, default: 0 }
  }

  connect() {
    this.element.classList.add(this.animationClassValue)
    if (this.delayValue > 0) {
      this.element.style.transitionDelay = `${this.delayValue}ms`
    }

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) {
      this.element.classList.add("is-visible")
      return
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
