import { Controller } from "@hotwired/stimulus"

// Keeps the stack list mounted while a nested Turbo Frame swaps only the
// selected frame's source. This mirrors a desktop debugger: selection changes
// in place without resetting the surrounding workspace.
export default class extends Controller {
  static get targets() {
    return ["frame", "sourceFrame"]
  }

  connect() {
    this.savedPageScrollY = null
    this.savedPanelScrollTop = null
    this.savedFrameListScrollTop = null
    this.restoreTimer = null
    this.syncSelection()
  }

  selectFrame(event) {
    const selectedFrame = event.currentTarget
    if (!(selectedFrame instanceof HTMLElement)) return

    // Capture before Turbo (or the browser's anchor handling) can move the
    // source frame into view. The request event is intentionally a second
    // capture point for frame-scope links and programmatic navigations.
    this.captureScrollPosition()

    this.frameTargets.forEach((frame) => {
      const isSelected = frame === selectedFrame
      frame.setAttribute("aria-current", isSelected ? "true" : "false")
      frame.closest(".frame-item")?.classList.toggle("is-active", isSelected)
    })

    if (this.hasSourceFrameTarget) {
      this.sourceFrameTarget.setAttribute("aria-busy", "true")
    }
  }

  onBeforeFetch(event) {
    if (!this.isSourceFrame(event.target) || !this.hasSourceFrameTarget) return

    // A nested Turbo Frame should feel like an in-place debugger selection.
    // Capture every scroll context that can own the visible position before
    // Turbo replaces the source excerpt. This also covers browsers that
    // attempt to scroll the frame into view while it is loading.
    this.captureScrollPosition()
    this.sourceFrameTarget.setAttribute("aria-busy", "true")
  }

  onFrameLoad(event) {
    if (!this.isSourceFrame(event.target) && !this.hasSavedScrollPosition()) return

    if (this.isSourceFrame(event.target)) event.target.setAttribute("aria-busy", "false")
    this.restoreScrollPosition()
  }

  captureScrollPosition() {
    this.savedPageScrollY = window.scrollY
    const panel = this.element.closest(".detail-panel")
    const frameList = this.element.querySelector(".frame-list")
    this.savedPanelScrollTop = panel ? panel.scrollTop : null
    this.savedFrameListScrollTop = frameList ? frameList.scrollTop : null
  }

  hasSavedScrollPosition() {
    return this.savedPageScrollY !== null || this.savedPanelScrollTop !== null || this.savedFrameListScrollTop !== null
  }

  restoreScrollPosition() {
    if (!this.hasSavedScrollPosition()) return

    if (this.restoreTimer) window.clearTimeout(this.restoreTimer)

    const restore = () => {
      if (typeof this.savedPageScrollY === "number") {
        window.scrollTo({ top: this.savedPageScrollY, left: window.scrollX, behavior: "auto" })
      }

      const panel = this.element.closest(".detail-panel")
      if (panel && typeof this.savedPanelScrollTop === "number") panel.scrollTop = this.savedPanelScrollTop

      const frameList = this.element.querySelector(".frame-list")
      if (frameList && typeof this.savedFrameListScrollTop === "number") frameList.scrollTop = this.savedFrameListScrollTop
    }

    // Turbo has completed the frame render at this point, but a browser may
    // apply its own anchor adjustment in a later layout pass. Re-apply over
    // a short settling window so selecting a frame never changes the user's
    // investigation position.
    restore()
    window.requestAnimationFrame(() => {
      restore()
      window.requestAnimationFrame(restore)
    })
    this.restoreTimer = window.setTimeout(() => {
      restore()
      this.savedPageScrollY = null
      this.savedPanelScrollTop = null
      this.savedFrameListScrollTop = null
      this.restoreTimer = null
    }, 350)
  }

  syncSelection() {
    const selectedFrame = this.frameTargets.find((frame) => frame.getAttribute("aria-current") === "true")
    if (!selectedFrame) return

    selectedFrame.closest(".frame-item")?.classList.add("is-active")
  }

  isSourceFrame(target) {
    return target instanceof HTMLElement && target.id === "stack_frame_source"
  }
}
