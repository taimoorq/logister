import { Controller } from "@hotwired/stimulus"

// Drives the project inbox workbench:
//   - Debounced search (submits the search form into the inbox turbo-frame)
//   - Filter tab active-state sync
//   - Row selection highlight
export default class extends Controller {
  static get targets() {
    return ["assigneeField", "assigneeForm", "clearProfileLink", "detailPane", "filterLink", "filterField", "listPane", "searchForm", "searchInput"]
  }

  connect() {
    this._searchTimer = null
    this.savedListScrollTop = null
    this.previousSelectedRowId = null
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

  submitAssigneeFilter(event) {
    const form = event.currentTarget.form || (this.hasAssigneeFormTarget ? this.assigneeFormTarget : null)
    if (!form) return

    if (this.hasAssigneeFieldTarget) {
      this.assigneeFieldTarget.value = event.currentTarget.value || "all"
    }

    form.requestSubmit()
  }

  submitForm(event) {
    const form = event.currentTarget.form
    if (form) form.requestSubmit()
  }

  // ── Filter tab switching ─────────────────────────────────────────────────
  activateFilter(event) {
    const link = event.currentTarget
    this.filterLinkTargets.forEach(currentLink => {
      const isActive = currentLink === link
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
    if (row) this.selectRowOptimistically(row)
  }

  openRow(event) {
    const target = event.target
    if (target && typeof target.closest === "function" && target.closest("a, button, input, textarea, select, summary")) {
      return
    }

    const row = event.currentTarget
    const link = row && typeof row.querySelector === "function" ? row.querySelector("a.error-row-link") : null
    if (!link) return

    link.click()
  }

  openRowKey(event) {
    event.preventDefault()
    this.openRow(event)
  }

  onDetailLoaded(event) {
    this.onFrameLoaded(event)
  }

  setSelectedRow(row) {
    this.element.querySelectorAll(".inbox-table tbody tr").forEach(currentRow => {
      const isSelected = currentRow === row
      currentRow.setAttribute("aria-selected", isSelected ? "true" : "false")
    })
  }

  selectRowOptimistically(row) {
    const selected = this.element.querySelector(".inbox-table tbody tr[aria-selected='true']")
    if (this.previousSelectedRowId === null) this.previousSelectedRowId = selected ? selected.id : ""
    this.setSelectedRow(row)
  }

  onBeforeFetch(event) {
    const target = event.target
    if (!(target instanceof HTMLElement)) return
    if (target.id === "error_detail") {
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

      this.savedListScrollTop = null
      this.previousSelectedRowId = null
      this.setBusy(this.hasDetailPaneTarget ? this.detailPaneTarget : null, false)
    } else if (frame.id === "project_inbox") {
      this.syncControlsFromFrame(frame)
      this.setBusy(this.hasListPaneTarget ? this.listPaneTarget : null, false)
    }
  }

  onFetchError(event) {
    if (!this.managesRequestTarget(event.target)) return

    if (this.previousSelectedRowId) {
      const previous = document.getElementById(this.previousSelectedRowId)
      if (previous) this.setSelectedRow(previous)
    } else if (this.previousSelectedRowId === "") {
      this.element.querySelectorAll(".inbox-table tbody tr").forEach((row) => row.setAttribute("aria-selected", "false"))
    }
    this.previousSelectedRowId = null
    this.savedListScrollTop = null
    const inboxFrame = document.getElementById("project_inbox")
    if (inboxFrame) this.syncControlsFromFrame(inboxFrame)
    this.clearBusyState()
  }

  onSubmitStart(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || !form.closest("#error_detail")) return

    this.setBusy(this.hasDetailPaneTarget ? this.detailPaneTarget : null, true)
  }

  onSubmitEnd(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || !form.closest("#error_detail")) return

    this.setBusy(this.hasDetailPaneTarget ? this.detailPaneTarget : null, false)
  }

  syncControlsFromFrame(frame) {
    const stateElement = frame.querySelector("[data-inbox-state-url]")
    const stateUrl = stateElement ? stateElement.dataset.inboxStateUrl : null
    if (!stateUrl) return

    const url = new URL(stateUrl, window.location.origin)
    const state = url.searchParams
    this.element.querySelectorAll(".inbox-workbench-filters form [name]").forEach((control) => {
      if (!(control instanceof HTMLInputElement || control instanceof HTMLSelectElement || control instanceof HTMLTextAreaElement)) return
      if (["authenticity_token", "utf8", "_method"].includes(control.name)) return
      if (control === document.activeElement && control.name === "q") return

      if (control instanceof HTMLInputElement && ["checkbox", "radio"].includes(control.type)) {
        control.checked = state.getAll(control.name).includes(control.value)
      } else if (control instanceof HTMLSelectElement && control.multiple) {
        const selectedValues = state.getAll(control.name)
        Array.from(control.options).forEach((option) => { option.selected = selectedValues.includes(option.value) })
      } else {
        control.value = state.get(control.name) || ""
      }
    })

    const filter = state.get("filter") || "unresolved"
    this.filterLinkTargets.forEach((link) => {
      const linkFilter = new URL(link.href, window.location.origin).searchParams.get("filter") || "unresolved"
      const linkUrl = new URL(stateUrl, window.location.origin)
      linkUrl.searchParams.set("filter", linkFilter)
      link.href = `${linkUrl.pathname}${linkUrl.search}${linkUrl.hash}`
      if (linkFilter === filter) {
        link.setAttribute("aria-current", "page")
      } else {
        link.removeAttribute("aria-current")
      }
    })

    if (this.hasClearProfileLinkTarget) {
      const clearUrl = new URL(stateUrl, window.location.origin)
      const profileKeys = (this.clearProfileLinkTarget.dataset.inboxProfileFilterKeys || "").split(",").filter(Boolean)
      profileKeys.forEach((key) => clearUrl.searchParams.delete(key))
      this.clearProfileLinkTarget.href = `${clearUrl.pathname}${clearUrl.search}${clearUrl.hash}`
    }
  }

  findListScroller() {
    return this.element.querySelector(".inbox-list-scroll")
  }

  managesRequestTarget(target) {
    if (!(target instanceof Element)) return false

    return ["error_detail", "project_inbox"].includes(target.id) ||
      Boolean(target.closest("#error_detail, #project_inbox"))
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
