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
    this.boundDetailLoaded = this.onDetailLoaded.bind(this)
    document.addEventListener("turbo:frame-load", this.boundDetailLoaded)
  }

  disconnect() {
    clearTimeout(this._searchTimer)
    document.removeEventListener("turbo:frame-load", this.boundDetailLoaded)
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
    this.setSelectedRow(row)
  }

  openDetail(event) {
    const link = event.currentTarget
    const row = link && typeof link.closest === "function" ? link.closest("tr") : null
    if (row) this.setSelectedRow(row)
  }

  openRow(event) {
    const target = event.target
    if (target && typeof target.closest === "function" && target.closest("a, button, input, textarea, select, summary")) {
      return
    }

    const row = event.currentTarget
    const link = row && typeof row.querySelector === "function" ? row.querySelector("a.error-row-link") : null
    if (!link) return

    this.setSelectedRow(row)
    this.visitDetail(link.href)
  }

  openRowKey(event) {
    event.preventDefault()
    this.openRow(event)
  }

  visitDetail(url) {
    const turbo = window.Turbo
    if (turbo && typeof turbo.visit === "function") {
      turbo.visit(url, { frame: "error_detail", action: "advance" })
      return
    }

    const frame = document.getElementById("error_detail")
    if (frame && "src" in frame) {
      frame.setAttribute("src", url)
      return
    }

    window.location.href = url
  }

  onDetailLoaded(event) {
    const frame = event.target
    if (!(frame instanceof HTMLElement) || frame.id !== "error_detail") return

    if (window.matchMedia("(max-width: 1023px)").matches) {
      frame.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }

  setSelectedRow(row) {
    this.element.querySelectorAll(".inbox-table tbody tr").forEach(r => r.classList.remove("is-selected"))
    row.classList.add("is-selected")
  }
}
