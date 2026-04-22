import { Controller } from "@hotwired/stimulus"

// Drives the project inbox workbench:
//   - Debounced search (submits the search form into the inbox turbo-frame)
//   - Filter tab active-state sync
//   - Row selection highlight
export default class extends Controller {
  static get targets() {
    return ["detailPane", "filterLink", "filterField", "listPane", "searchForm", "searchInput"]
  }

  connect() {
    this._searchTimer = null
    this.savedPageScrollY = null
    this.savedListScrollTop = null
    this.clearBusyState()
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
    this.filterLinkTargets.forEach(currentLink => {
      const isActive = currentLink === link
      currentLink.classList.toggle("is-active", isActive)
      if (isActive) {
        currentLink.setAttribute("aria-current", "page")
      } else {
        currentLink.removeAttribute("aria-current")
      }
    })

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
    const frame = document.getElementById("error_detail")
    if (frame) {
      frame.setAttribute("src", url)
      return
    }

    const turbo = window.Turbo
    if (turbo && typeof turbo.visit === "function") {
      turbo.visit(url)
      return
    }

    window.location.assign(url)
  }

  onDetailLoaded(event) {
    this.onFrameLoaded(event)
  }

  setSelectedRow(row) {
    this.element.querySelectorAll(".inbox-table tbody tr").forEach(currentRow => {
      const isSelected = currentRow === row
      currentRow.classList.toggle("is-selected", isSelected)
      currentRow.setAttribute("aria-selected", isSelected ? "true" : "false")
    })
  }

  onBeforeFetch(event) {
    const target = event.target
    if (!(target instanceof HTMLElement)) return
    if (target.id === "error_detail") {
      this.savedPageScrollY = window.scrollY
      const list = this.findListScroller()
      this.savedListScrollTop = list ? list.scrollTop : null
      this.setBusy(this.hasDetailPaneTarget ? this.detailPaneTarget : null, true)
    } else if (target.id === "project_inbox") {
      this.setBusy(this.hasListPaneTarget ? this.listPaneTarget : null, true)
    }
  }

  onFrameLoaded(event) {
    const frame = event.target
    if (!(frame instanceof HTMLElement)) return

    if (frame.id === "error_detail") {
      if (typeof this.savedListScrollTop === "number") {
        const list = this.findListScroller()
        if (list) list.scrollTop = this.savedListScrollTop
      }

      if (typeof this.savedPageScrollY === "number") {
        window.scrollTo({ top: this.savedPageScrollY, left: 0, behavior: "auto" })
      }

      this.savedListScrollTop = null
      this.savedPageScrollY = null
      this.setBusy(this.hasDetailPaneTarget ? this.detailPaneTarget : null, false)
    } else if (frame.id === "project_inbox") {
      this.setBusy(this.hasListPaneTarget ? this.listPaneTarget : null, false)
    }
  }

  findListScroller() {
    return this.element.querySelector(".inbox-list-scroll")
  }

  clearBusyState() {
    if (this.hasListPaneTarget) this.setBusy(this.listPaneTarget, false)
    if (this.hasDetailPaneTarget) this.setBusy(this.detailPaneTarget, false)
  }

  setBusy(element, busy) {
    if (!element) return
    element.setAttribute("aria-busy", busy ? "true" : "false")
  }
}
