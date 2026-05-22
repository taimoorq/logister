import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

export default class extends Controller {
  static targets = ["chart"]
  static values = {
    payload: Object
  }

  connect() {
    this.payload = this.hasPayloadValue ? this.payloadValue : { segments: [], requests: [] }
    this.chart = echarts.init(this.chartTarget, null, { renderer: "canvas" })
    this.render()

    this.resizeObserver = "ResizeObserver" in window ? new ResizeObserver(() => this.queueResize()) : null
    this.resizeObserver?.observe(this.element)
    this.resizeObserver?.observe(this.chartTarget)
    this.resizeHandler = () => this.queueResize()
    window.addEventListener("resize", this.resizeHandler)
  }

  disconnect() {
    window.removeEventListener("resize", this.resizeHandler)
    this.resizeObserver?.disconnect()
    cancelAnimationFrame(this.resizeFrame)
    this.chart?.dispose()
  }

  render() {
    const requests = this.payload.requests || []
    const segments = this.payload.segments || []
    const labels = requests.map((request) => request.label || request.name || "request")
    const hasData = requests.some((request) => Number(request.duration_ms) > 0)

    this.chart.setOption({
      color: segments.map((segment) => segment.color),
      animationDuration: 250,
      tooltip: {
        trigger: "axis",
        axisPointer: { type: "shadow" },
        valueFormatter: (value) => `${Number(value || 0).toFixed(2)} ms`
      },
      legend: {
        type: "scroll",
        top: 0,
        itemWidth: 10,
        itemHeight: 10,
        textStyle: { color: "#475569", fontSize: 11, fontWeight: 600 }
      },
      grid: { top: 38, right: 18, bottom: 30, left: 148, containLabel: true },
      xAxis: {
        type: "value",
        axisLabel: { color: "#64748b", formatter: "{value} ms" },
        splitLine: { lineStyle: { color: "#e2e8f0" } }
      },
      yAxis: {
        type: "category",
        data: labels,
        inverse: true,
        axisTick: { show: false },
        axisLabel: { color: "#334155", fontSize: 11, width: 132, overflow: "truncate" }
      },
      graphic: emptyGraphic(!hasData, "No request timing data"),
      series: segments.map((segment) => ({
        name: segment.label,
        type: "bar",
        stack: "duration",
        barWidth: 14,
        emphasis: { focus: "series" },
        data: requests.map((request) => Number(request.segments?.[segment.key] || 0))
      }))
    }, true)
  }

  queueResize() {
    cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = requestAnimationFrame(() => this.chart?.resize())
  }
}

function emptyGraphic(show, text) {
  if (!show) return []

  return [{
    type: "text",
    left: "center",
    top: "middle",
    style: {
      text,
      fill: "#64748b",
      fontSize: 13,
      fontWeight: 600
    }
  }]
}
