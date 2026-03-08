import { Controller } from "@hotwired/stimulus"

// Drives the project inbox workbench:
//   - Debounced search (submits the search form into the inbox turbo-frame)
//   - Filter tab active-state sync
//   - Row selection highlight
export default class extends Controller {
  static get targets() {
    return ["filterLink", "filterField", "searchForm", "searchInput"]
  }

  connect() {
    this._searchTimer = null
  }

  disconnect() {
    clearTimeout(this._searchTimer)
  }

  // ── Debounced search ─────────────────────────────────────────────────────
  debouncedSearch() {
    clearTimeout(this._searchTimer)
    this._searchTimer = setTimeout(() => {
      this.searchFormTarget.requestSubmit()
    }, 240)
  }

  onSearchSubmit() {
    // Form naturally submits into turbo-frame; hook available for future use.
  }

  // ── Filter tab switching ─────────────────────────────────────────────────
  activateFilter(event) {
    const link = event.currentTarget
    this.filterLinkTargets.forEach(l => l.classList.remove("is-active"))
    link.classList.add("is-active")

    // Keep the hidden filter field in sync so search submits the right filter
    if (this.hasFilterFieldTarget) {
      const url = new URL(link.href, window.location.origin)
      this.filterFieldTarget.value = url.searchParams.get("filter") || "unresolved"
    }
  }

  // ── Row selection ────────────────────────────────────────────────────────
  selectRow(event) {
    const row = event.target.closest("tr")
    if (!row) return
    this.element.querySelectorAll(".inbox-table tbody tr").forEach(r => r.classList.remove("is-selected"))
    row.classList.add("is-selected")
  }
}
