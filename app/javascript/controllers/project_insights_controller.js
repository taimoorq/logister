import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

const SERIES_COLORS = ["#2563eb", "#059669", "#ef4444", "#8b5cf6", "#d97706", "#0f766e", "#475569", "#db2777"]
const EVENT_COLORS = {
  error: "#ef4444",
  log: "#64748b",
  metric: "#8b5cf6",
  transaction: "#059669",
  check_in: "#2563eb"
}

export default class extends Controller {
  static targets = [
    "metricChart",
    "eventChart",
    "summary",
    "metricList",
    "activeMetrics",
    "environmentSelect",
    "releaseSelect",
    "refreshSelect",
    "status",
    "windowButton",
    "recentEvents"
  ]
  static values = {
    payload: Object
  }

  connect() {
    this.payload = this.hasPayloadValue ? this.payloadValue : {}
    const savedState = this.readSavedState()
    this.window = savedState.window || this.payload.default_window || "24h"
    this.environment = savedState.environment || ""
    this.release = savedState.release || ""
    this.refreshSeconds = Number(savedState.refreshSeconds ?? this.payload.refresh_seconds ?? 30)
    this.catalog = this.payload.metric_catalog || []
    this.catalogByKey = new Map(this.catalog.map((metric) => [metric.key, metric]))
    this.eventTypes = this.payload.event_types || []
    this.selectedMetrics = Array.isArray(savedState.metrics) && savedState.metrics.length > 0
      ? savedState.metrics.slice(0, 8)
      : this.normalizeSelectedMetrics(this.payload.default_metrics || [])
    this.charts = {}

    this.initializeCharts()
    this.refreshSelectTarget.value = String(this.refreshSeconds)
    this.renderWindowButtons()
    this.renderMetricControls()
    this.fetchData()
    this.scheduleRefresh()

    this.resizeHandler = () => this.queueResize()
    window.addEventListener("resize", this.resizeHandler)

    if ("ResizeObserver" in window) {
      this.resizeObserver = new ResizeObserver(() => this.queueResize())
      this.resizeObserver.observe(this.element)
      this.resizeObserver.observe(this.metricChartTarget)
      this.resizeObserver.observe(this.eventChartTarget)
    }
  }

  disconnect() {
    this.abortController?.abort()
    this.resizeObserver?.disconnect()
    window.removeEventListener("resize", this.resizeHandler)
    clearInterval(this.refreshTimer)
    cancelAnimationFrame(this.resizeFrame)
    Object.values(this.charts).forEach((chart) => chart.dispose())
  }

  selectWindow(event) {
    event.preventDefault()
    const window = event.currentTarget.dataset.window
    if (!window || window === this.window) return

    this.window = window
    this.renderWindowButtons()
    this.saveState()
    this.fetchData()
  }

  changeEnvironment(event) {
    this.environment = event.currentTarget.value
    this.saveState()
    this.fetchData()
  }

  changeRelease(event) {
    this.release = event.currentTarget.value
    this.saveState()
    this.fetchData()
  }

  changeRefresh(event) {
    this.refreshSeconds = Number(event.currentTarget.value)
    this.scheduleRefresh()
    this.saveState()
    this.setStatus(this.refreshSeconds > 0 ? `Live every ${this.refreshSeconds}s` : "Live refresh off")
  }

  refreshNow(event) {
    event?.preventDefault()
    this.fetchData()
  }

  addMetric(event) {
    event.preventDefault()
    const metricKey = event.currentTarget.dataset.metricKey
    if (!metricKey || this.selectedMetrics.includes(metricKey)) return

    this.selectedMetrics = [...this.selectedMetrics, metricKey].slice(0, 8)
    this.renderMetricControls()
    this.saveState()
    this.fetchData()
  }

  removeMetric(event) {
    event.preventDefault()
    const metricKey = event.currentTarget.dataset.metricKey
    this.selectedMetrics = this.selectedMetrics.filter((key) => key !== metricKey)
    this.renderMetricControls()
    this.saveState()
    this.fetchData()
  }

  initializeCharts() {
    this.charts.metrics = echarts.init(this.metricChartTarget, null, { renderer: "canvas" })
    this.charts.events = echarts.init(this.eventChartTarget, null, { renderer: "canvas" })
  }

  fetchData() {
    this.abortController?.abort()
    this.abortController = new AbortController()
    const controller = this.abortController

    this.setLoading(true)
    this.setStatus("Refreshing...")

    fetch(this.insightsUrl(), {
      headers: { Accept: "application/json" },
      signal: controller.signal
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Project insights request failed: ${response.status}`)

        return response.json()
      })
      .then((data) => this.renderData(data))
      .catch((error) => {
        if (error.name === "AbortError") return

        console.warn("[Logister] Project insights failed to render", error)
        this.renderError()
      })
      .finally(() => {
        if (this.abortController === controller) this.setLoading(false)
      })
  }

  insightsUrl() {
    const url = new URL(this.payload.endpoint || window.location.pathname, window.location.origin)
    url.searchParams.set("window", this.window)

    if (this.environment) url.searchParams.set("environment", this.environment)
    if (this.release) url.searchParams.set("release", this.release)
    this.selectedMetrics.forEach((metricKey) => url.searchParams.append("metrics[]", metricKey))

    return url
  }

  renderData(data) {
    this.catalog = data.metric_catalog || this.catalog
    this.catalogByKey = new Map(this.catalog.map((metric) => [metric.key, metric]))
    this.eventTypes = data.event_type_catalog || this.eventTypes
    this.selectedMetrics = data.selected_metrics || this.selectedMetrics

    this.renderFilterSelects(data)
    this.renderMetricControls()
    this.renderSummary(data.summary || {})
    this.renderMetricChart(data)
    this.renderEventChart(data)
    this.renderRecentEvents(data.recent_events || [])
    this.saveState()
    this.setStatus(`Updated ${timeOnly(data.generated_at || new Date())}`)
  }

  renderError() {
    this.setStatus("Unable to load dashboard data")
    this.summaryTarget.innerHTML = this.summaryCell("--", "Events") +
      this.summaryCell("--", "Errors") +
      this.summaryCell("--", "Transactions") +
      this.summaryCell("--", "Metrics")
    this.charts.metrics.setOption({ graphic: emptyGraphic(true, "Unable to load metrics"), series: [] }, true)
    this.charts.events.setOption({ graphic: emptyGraphic(true, "Unable to load activity"), series: [] }, true)
  }

  renderFilterSelects(data) {
    populateSelect(this.environmentSelectTarget, data.environments || [], this.environment, "All environments")
    populateSelect(this.releaseSelectTarget, data.releases || [], this.release, "All releases")
  }

  renderWindowButtons() {
    this.windowButtonTargets.forEach((button) => {
      const active = button.dataset.window === this.window
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", String(active))
    })
  }

  renderMetricControls() {
    this.renderMetricCatalog()
    this.renderActiveMetrics()
  }

  renderMetricCatalog() {
    if (this.catalog.length === 0) {
      this.metricListTarget.innerHTML = '<p class="project-insights-empty">No metrics collected in this window.</p>'
      return
    }

    this.metricListTarget.innerHTML = this.catalog.map((metric) => {
      const selected = this.selectedMetrics.includes(metric.key)
      const events = metric.events ? `<span>${formatNumber(metric.events)} events</span>` : ""

      return `
        <button type="button"
                class="project-insights-metric ${selected ? "is-selected" : ""}"
                data-action="project-insights#addMetric"
                data-metric-key="${escapeHtml(metric.key)}"
                ${selected ? "disabled" : ""}>
          <span class="project-insights-metric-main">
            <strong>${escapeHtml(metric.label)}</strong>
            <span>${escapeHtml(metric.description || metric.source || "")}</span>
          </span>
          <span class="project-insights-metric-meta">
            <span>${escapeHtml(metric.source || "Metric")}</span>
            <span>${escapeHtml(metric.unit || "count")}</span>
            ${events}
          </span>
        </button>
      `
    }).join("")
  }

  renderActiveMetrics() {
    if (this.selectedMetrics.length === 0) {
      this.activeMetricsTarget.innerHTML = '<p class="project-insights-empty">Add a metric to start charting.</p>'
      return
    }

    this.activeMetricsTarget.innerHTML = this.selectedMetrics.map((metricKey) => {
      const metric = this.catalogByKey.get(metricKey) || { label: metricKey, key: metricKey }

      return `
        <button type="button"
                class="project-insights-active-chip"
                data-action="project-insights#removeMetric"
                data-metric-key="${escapeHtml(metric.key)}"
                aria-label="Remove ${escapeHtml(metric.label)}">
          <span>${escapeHtml(metric.label)}</span>
          <span aria-hidden="true">x</span>
        </button>
      `
    }).join("")
  }

  renderSummary(summary) {
    this.summaryTarget.innerHTML = this.summaryCell(summary.events, "Events") +
      this.summaryCell(summary.errors, "Errors") +
      this.summaryCell(summary.transactions, "Transactions") +
      this.summaryCell(summary.metrics, "Metrics")
  }

  summaryCell(value, label) {
    return `
      <div class="project-insights-summary-cell">
        <strong>${formatNumber(value)}</strong>
        <span>${escapeHtml(label)}</span>
      </div>
    `
  }

  renderMetricChart(data) {
    const metricSeries = data.metric_series || []
    const timestamps = data.buckets || []
    const labels = timestamps.map((timestamp) => shortTimeLabel(timestamp, data.bucket))
    const definitionsByName = new Map(metricSeries.map((series) => [series.label, series]))
    const series = metricSeries.map((metric, index) => ({
      name: metric.label,
      type: "line",
      yAxisIndex: metric.unit === "ms" ? 1 : 0,
      smooth: true,
      showSymbol: false,
      symbolSize: 5,
      lineStyle: { width: 2 },
      emphasis: { focus: "series" },
      color: SERIES_COLORS[index % SERIES_COLORS.length],
      data: (metric.data || []).map((point) => Number(point.value) || 0)
    }))
    const hasData = series.some((line) => line.data.some((value) => value > 0))

    this.charts.metrics.setOption({
      aria: { enabled: true },
      color: SERIES_COLORS,
      graphic: emptyGraphic(!hasData, series.length > 0 ? "No values in this slice" : "Add a metric to chart"),
      grid: { left: 48, right: 54, top: 42, bottom: 34 },
      legend: {
        top: 0,
        type: "scroll",
        icon: "roundRect",
        textStyle: { color: "#475569", fontSize: 11 }
      },
      tooltip: {
        trigger: "axis",
        formatter: (params) => metricTooltipFormatter(params, definitionsByName)
      },
      xAxis: {
        type: "category",
        boundaryGap: false,
        data: labels,
        axisTick: { show: false },
        axisLabel: { color: "#64748b", hideOverlap: true }
      },
      yAxis: [
        {
          type: "value",
          name: "count",
          minInterval: 1,
          axisLabel: { formatter: compactNumber, color: "#64748b" },
          splitLine: { lineStyle: { color: "#e2e8f0" } }
        },
        {
          type: "value",
          name: "ms",
          axisLabel: { formatter: compactNumber, color: "#64748b" },
          splitLine: { show: false }
        }
      ],
      series
    }, true)
  }

  renderEventChart(data) {
    const rows = data.event_timeline || []
    const labels = rows.map((row) => shortTimeLabel(row.timestamp, data.bucket))
    const series = this.eventTypes.map((eventType) => ({
      name: eventType.label,
      type: "bar",
      stack: "events",
      barMaxWidth: 18,
      emphasis: { focus: "series" },
      itemStyle: { color: EVENT_COLORS[eventType.key] || eventType.color },
      data: rows.map((row) => Number(row[eventType.key]) || 0)
    }))
    const hasData = series.some((bar) => bar.data.some((value) => value > 0))

    this.charts.events.setOption({
      aria: { enabled: true },
      graphic: emptyGraphic(!hasData, "No activity in this slice"),
      grid: { left: 42, right: 16, top: 34, bottom: 34 },
      legend: {
        top: 0,
        type: "scroll",
        icon: "roundRect",
        textStyle: { color: "#475569", fontSize: 11 }
      },
      tooltip: { trigger: "axis", formatter: eventTooltipFormatter },
      xAxis: {
        type: "category",
        data: labels,
        axisTick: { show: false },
        axisLabel: { color: "#64748b", hideOverlap: true }
      },
      yAxis: {
        type: "value",
        minInterval: 1,
        axisLabel: { formatter: compactNumber, color: "#64748b" },
        splitLine: { lineStyle: { color: "#e2e8f0" } }
      },
      series
    }, true)
  }

  renderRecentEvents(events) {
    if (events.length === 0) {
      this.recentEventsTarget.innerHTML = '<p class="project-insights-empty">No matching events yet.</p>'
      return
    }

    this.recentEventsTarget.innerHTML = events.map((event) => `
      <div class="project-insights-recent-row">
        <span class="project-insights-event-dot" style="background-color: ${EVENT_COLORS[event.event_type] || "#64748b"}"></span>
        <div>
          <div class="project-insights-recent-title">
            <strong>${escapeHtml(event.message || event.label || "Event")}</strong>
            <span>${escapeHtml(event.label || event.event_type || "Event")}</span>
          </div>
          <div class="project-insights-recent-meta">
            <span>${escapeHtml(timeOnly(event.occurred_at))}</span>
            <span>${escapeHtml(event.environment || "unknown")}</span>
            ${event.release ? `<span>${escapeHtml(event.release)}</span>` : ""}
            ${event.duration_ms ? `<span>${formatValue(event.duration_ms, "ms")}</span>` : ""}
          </div>
        </div>
      </div>
    `).join("")
  }

  scheduleRefresh() {
    clearInterval(this.refreshTimer)

    if (this.refreshSeconds > 0) {
      this.refreshTimer = setInterval(() => this.fetchData(), this.refreshSeconds * 1000)
    }
  }

  normalizeSelectedMetrics(metricKeys) {
    const available = new Set(this.catalog.map((metric) => metric.key))
    const selected = metricKeys.filter((metricKey) => available.has(metricKey))

    return selected.length > 0 ? selected : this.catalog.slice(0, 4).map((metric) => metric.key)
  }

  readSavedState() {
    try {
      return JSON.parse(window.localStorage.getItem(this.storageKey())) || {}
    } catch (_error) {
      return {}
    }
  }

  saveState() {
    try {
      window.localStorage.setItem(this.storageKey(), JSON.stringify({
        window: this.window,
        environment: this.environment,
        release: this.release,
        refreshSeconds: this.refreshSeconds,
        metrics: this.selectedMetrics
      }))
    } catch (_error) {
      // Ignore browsers or privacy modes that block localStorage.
    }
  }

  storageKey() {
    return `logister.project-insights.${this.payload.project_uuid || window.location.pathname}`
  }

  setLoading(loading) {
    Object.values(this.charts).forEach((chart) => {
      if (loading) {
        chart.showLoading("default", { text: "", color: "#2563eb", maskColor: "rgba(248, 250, 252, 0.78)" })
      } else {
        chart.hideLoading()
      }
    })
  }

  setStatus(text) {
    this.statusTarget.textContent = text
  }

  queueResize() {
    cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = requestAnimationFrame(() => {
      Object.values(this.charts).forEach((chart) => chart.resize())
    })
  }
}

function populateSelect(target, options, selectedValue, emptyLabel) {
  const rows = options || []
  const selectedMissing = selectedValue && !rows.some((row) => row.name === selectedValue)
  const optionHtml = [
    `<option value="">${escapeHtml(emptyLabel)}</option>`,
    selectedMissing ? `<option value="${escapeHtml(selectedValue)}">${escapeHtml(selectedValue)}</option>` : "",
    ...rows.map((row) => `<option value="${escapeHtml(row.name)}">${escapeHtml(row.name)}</option>`)
  ].join("")

  target.innerHTML = optionHtml
  target.value = selectedValue || ""
}

function emptyGraphic(show, text) {
  if (!show) return []

  return [{
    type: "text",
    left: "center",
    top: "middle",
    silent: true,
    style: {
      text,
      fill: "#64748b",
      fontSize: 12,
      fontWeight: 600
    }
  }]
}

function metricTooltipFormatter(params, definitionsByName) {
  if (!Array.isArray(params) || params.length === 0) return ""

  const rows = params.filter((item) => Number(item.value) > 0).map((item) => {
    const definition = definitionsByName.get(item.seriesName) || {}
    return `${item.marker}${escapeHtml(item.seriesName)}: ${formatValue(item.value, definition.unit)}`
  })

  return `${escapeHtml(params[0].axisValueLabel || "")}<br>${rows.length > 0 ? rows.join("<br>") : "No values"}`
}

function eventTooltipFormatter(params) {
  if (!Array.isArray(params) || params.length === 0) return ""

  const rows = params.filter((item) => Number(item.value) > 0).map((item) => (
    `${item.marker}${escapeHtml(item.seriesName)}: ${formatNumber(item.value)}`
  ))

  return `${escapeHtml(params[0].axisValueLabel || "")}<br>${rows.length > 0 ? rows.join("<br>") : "No activity"}`
}

function formatNumber(value) {
  if (value === "--") return value

  return new Intl.NumberFormat().format(Number(value) || 0)
}

function compactNumber(value) {
  return new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(Number(value) || 0)
}

function formatValue(value, unit) {
  const number = Number(value) || 0
  const formatted = new Intl.NumberFormat(undefined, { maximumFractionDigits: unit === "ms" ? 1 : 0 }).format(number)

  return unit === "ms" ? `${formatted} ms` : formatted
}

function shortTimeLabel(value, bucket) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  if (bucket === "day") {
    return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(date)
  }

  if (bucket === "minute") {
    return new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(date)
  }

  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "numeric" }).format(date)
}

function timeOnly(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ""

  return new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit", second: "2-digit" }).format(date)
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
