import { Controller } from "@hotwired/stimulus"
import { metricSeriesFromEventTimeline, metricTimelineOption } from "charts/telemetry_timeline"

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
    cancelAnimationFrame(this.renderFrame)
    cancelAnimationFrame(this.resizeFrame)
    this.chart?.dispose()
  }

  beforeCache() {
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    cancelAnimationFrame(this.renderFrame)
    cancelAnimationFrame(this.resizeFrame)
    this.chart?.dispose()
    this.chart = null
    this.chartTarget.replaceChildren()
  }

  async loadChart() {
    try {
      const echarts = await import("echarts")
      if (!this.connected) return

      await this.waitForChartBox()
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
    const rows = this.payload.rows || []
    const eventTypes = this.payload.event_types || []

    this.chart.setOption(metricTimelineOption({
      labels: rows.map((row) => dashboardTimeLabel(row.timestamp)),
      metricSeries: metricSeriesFromEventTimeline({ rows, eventTypes }),
      emptyText: "No telemetry in the last 24 hours",
      noSeriesText: "No telemetry series",
      includeSliderZoom: false,
      grid: { left: 48, right: 54, top: 42, bottom: 36 }
    }), true)
    this.chartTarget.dataset.rendered = "true"
  }

  queueResize() {
    cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = requestAnimationFrame(() => this.chart?.resize())
  }

  waitForChartBox(remainingFrames = 10) {
    const rect = this.chartTarget.getBoundingClientRect()
    if ((rect.width > 0 && rect.height > 0) || remainingFrames <= 0) return Promise.resolve()

    return new Promise((resolve) => {
      this.renderFrame = requestAnimationFrame(() => {
        resolve(this.waitForChartBox(remainingFrames - 1))
      })
    })
  }

  isTurboPreview() {
    return document.documentElement.hasAttribute("data-turbo-preview")
  }
}

function dashboardTimeLabel(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  return new Intl.DateTimeFormat(undefined, { hour: "numeric" }).format(date)
}
