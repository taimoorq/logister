import { Controller } from "@hotwired/stimulus"

// Filters project cards on the projects index by name/slug (client-side).
// Use with data-controller="project-search" on a wrapper and data-action="input->project-search#filter"
// on the search input. Each card should have data-project-name and optionally data-project-slug.
export default class extends Controller {
  static get values() {
    return { selector: { type: String, default: "[data-project-name]" } }
  }

  filter(event) {
    const query = (event.target.value || "").trim().toLowerCase()
    const cards = this.element.querySelectorAll(this.selectorValue)

    cards.forEach((card) => {
      const name = (card.dataset.projectName || "").toLowerCase()
      const slug = (card.dataset.projectSlug || "").toLowerCase()
      const match = !query || name.includes(query) || slug.includes(query)
      card.classList.toggle("hidden", !match)
    })
  }
}
