import { Controller } from "@hotwired/stimulus"
import { telemetryTimelineOption } from "../charts/telemetry_timeline.js"

export default class extends Controller {
  static targets = ["chart"]
  static values = {
    payload: Object
  }

  connect() {
    this.connected = true
    this.payload = this.hasPayloadValue ? this.payloadValue : { event_types: [], rows: [] }
    this.beforeCacheHandler = () => this.beforeCache()
    this.resizeHandler = () => this.queueResize()

    if (this.isTurboPreview()) return

    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)
    window.addEventListener("resize", this.resizeHandler)
    this.loadChart()
  }

  disconnect() {
    this.connected = false
    document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
    window.removeEventListener("resize", this.resizeHandler)
    this.resizeObserver?.disconnect()
    cancelAnimationFrame(this.resizeFrame)
    this.chart?.dispose()
  }

  beforeCache() {
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    cancelAnimationFrame(this.resizeFrame)
    this.chart?.dispose()
    this.chart = null
    this.chartTarget.replaceChildren()
  }

  async loadChart() {
    try {
      const echarts = await import("echarts")
      if (!this.connected) return

      echarts.getInstanceByDom(this.chartTarget)?.dispose()
      this.chart = echarts.init(this.chartTarget, null, { renderer: "canvas" })
      this.renderChart()

      if ("ResizeObserver" in window) {
        this.resizeObserver = new ResizeObserver(() => this.queueResize())
        this.resizeObserver.observe(this.element)
        this.resizeObserver.observe(this.chartTarget)
      }
    } catch (error) {
      console.warn("[Logister] Project telemetry timeline failed to render", error)
    }
  }

  renderChart() {
    this.chart.setOption(telemetryTimelineOption({
      rows: this.payload.rows || [],
      eventTypes: this.payload.event_types || [],
      emptyText: "No telemetry in the last 24 hours"
    }), true)
  }

  queueResize() {
    cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = requestAnimationFrame(() => this.chart?.resize())
  }

  isTurboPreview() {
    return document.documentElement.hasAttribute("data-turbo-preview")
  }
}
