import { Controller } from "@hotwired/stimulus"

const SERIES_COLORS = ["#2563eb", "#059669", "#ef4444", "#8b5cf6", "#d97706", "#0f766e", "#475569", "#db2777"]
const EVENT_COLORS = {
  error: "#ef4444",
  log: "#64748b",
  metric: "#8b5cf6",
  transaction: "#059669",
  check_in: "#2563eb"
}
const METRIC_CATEGORY_ORDER = ["health", "activity", "performance", "monitors", "metrics", "other"]
const METRIC_CATEGORY_COPY = {
  health: { label: "Health", description: "Errors and user-impacting failures" },
  activity: { label: "Activity", description: "Events and logs moving through the app" },
  performance: { label: "Performance", description: "Transactions, database work, and durations" },
  monitors: { label: "Monitors", description: "Check-ins and background job heartbeats" },
  metrics: { label: "Custom metrics", description: "Application-specific counters and values" },
  other: { label: "Other signals", description: "Collected series outside the standard groups" }
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
    "attributeKeySelect",
    "attributeValueSelect",
    "attributeFilters",
    "refreshSelect",
    "status",
    "windowButton",
    "recentEvents"
  ]
  static values = {
    payload: Object
  }

  connect() {
    this.connected = true
    this.payload = this.hasPayloadValue ? this.payloadValue : {}
    const savedState = this.readSavedState()
    this.window = savedState.window || this.payload.default_window || "24h"
    this.environment = savedState.environment || ""
    this.release = savedState.release || ""
    this.refreshSeconds = Number(savedState.refreshSeconds ?? this.payload.refresh_seconds ?? 30)
    this.catalog = this.payload.metric_catalog || []
    this.catalogByKey = new Map(this.catalog.map((metric) => [metric.key, metric]))
    this.attributeCatalog = this.payload.attributes || []
    this.attributeByKey = new Map(this.attributeCatalog.map((attribute) => [attribute.key, attribute]))
    this.attributeFilters = normalizeAttributeFilters(savedState.attributeFilters || {})
    this.eventTypes = this.payload.event_types || []
    this.selectedMetrics = Array.isArray(savedState.metrics) && savedState.metrics.length > 0
      ? savedState.metrics.slice(0, 8)
      : this.normalizeSelectedMetrics(this.payload.default_metrics || [])
    this.charts = {}
    this.chartsReady = false

    this.refreshSelectTarget.value = String(this.refreshSeconds)
    this.renderWindowButtons()
    this.renderAttributeControls()
    this.renderMetricControls()
    this.setStatus("Loading charts...")
    this.loadCharts()

    this.resizeHandler = () => this.queueResize()
    window.addEventListener("resize", this.resizeHandler)
  }

  disconnect() {
    this.connected = false
    this.abortController?.abort()
    this.resizeObserver?.disconnect()
    window.removeEventListener("resize", this.resizeHandler)
    clearInterval(this.refreshTimer)
    cancelAnimationFrame(this.resizeFrame)
    Object.values(this.charts || {}).forEach((chart) => chart.dispose())
  }

  async loadCharts() {
    try {
      const echarts = await import("echarts")
      if (!this.connected) return

      this.initializeCharts(echarts)
      this.chartsReady = true
      this.fetchData()
      this.scheduleRefresh()
      this.observeChartResizes()
    } catch (error) {
      console.warn("[Logister] Project insights charts failed to load", error)
      this.setStatus("Unable to load charts")
    }
  }

  observeChartResizes() {
    if (!("ResizeObserver" in window)) return

    this.resizeObserver = new ResizeObserver(() => this.queueResize())
    this.resizeObserver.observe(this.element)
    this.resizeObserver.observe(this.metricChartTarget)
    this.resizeObserver.observe(this.eventChartTarget)
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

  changeAttributeKey() {
    this.renderAttributeValues()
  }

  addAttributeFilter(event) {
    event.preventDefault()

    const key = this.attributeKeySelectTarget.value
    const value = this.attributeValueSelectTarget.value
    if (!key || !value) return

    this.attributeFilters = { ...this.attributeFilters, [key]: value }
    this.renderAttributeControls()
    this.saveState()
    this.fetchData()
  }

  removeAttributeFilter(event) {
    event.preventDefault()

    const key = event.currentTarget.dataset.attributeKey
    if (!key) return

    const nextFilters = { ...this.attributeFilters }
    delete nextFilters[key]
    this.attributeFilters = nextFilters
    this.renderAttributeControls()
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

  initializeCharts(echarts) {
    this.charts.metrics = echarts.init(this.metricChartTarget, null, { renderer: "canvas" })
    this.charts.events = echarts.init(this.eventChartTarget, null, { renderer: "canvas" })
  }

  fetchData() {
    if (!this.chartsReady) return

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
    Object.entries(this.attributeFilters).forEach(([key, value]) => {
      if (key && value) url.searchParams.set(`attributes[${key}]`, value)
    })
    this.selectedMetrics.forEach((metricKey) => url.searchParams.append("metrics[]", metricKey))

    return url
  }

  renderData(data) {
    this.catalog = data.metric_catalog || this.catalog
    this.catalogByKey = new Map(this.catalog.map((metric) => [metric.key, metric]))
    this.attributeCatalog = data.attributes || this.attributeCatalog
    this.attributeByKey = new Map(this.attributeCatalog.map((attribute) => [attribute.key, attribute]))
    this.attributeFilters = attributeFiltersFromServer(data.attribute_filters) || this.attributeFilters
    this.eventTypes = data.event_type_catalog || this.eventTypes
    this.selectedMetrics = data.selected_metrics || this.selectedMetrics

    this.renderFilterSelects(data)
    this.renderAttributeControls()
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
    this.summaryTarget.innerHTML = this.summaryCell("--", "Events", "All matching signals") +
      this.summaryCell("--", "Errors", "Health signals") +
      this.summaryCell("--", "Transactions", "Performance spans") +
      this.summaryCell("--", "Metrics", "Custom measurements") +
      this.summaryCell("--", "Check-ins", "Monitors and jobs")
    this.charts.metrics.setOption({ graphic: emptyGraphic(true, "Unable to load metrics"), series: [] }, true)
    this.charts.events.setOption({ graphic: emptyGraphic(true, "Unable to load activity"), series: [] }, true)
  }

  renderFilterSelects(data) {
    populateSelect(this.environmentSelectTarget, data.environments || [], this.environment, "All environments")
    populateSelect(this.releaseSelectTarget, data.releases || [], this.release, "All releases")
  }

  renderAttributeControls() {
    if (!this.hasAttributeKeySelectTarget || !this.hasAttributeValueSelectTarget || !this.hasAttributeFiltersTarget) return

    const currentKey = this.attributeKeySelectTarget.value
    const selectedKey = this.attributeByKey.has(currentKey) ? currentKey : ""
    const optionHtml = [
      '<option value="">Choose attribute</option>',
      ...this.attributeCatalog.map((attribute) => (
        `<option value="${escapeHtml(attribute.key)}">${escapeHtml(attribute.label)} (${formatNumber(attribute.count)})</option>`
      ))
    ].join("")

    this.attributeKeySelectTarget.innerHTML = optionHtml
    this.attributeKeySelectTarget.value = selectedKey
    this.renderAttributeValues()
    this.renderAttributeFilters()
  }

  renderAttributeValues() {
    if (!this.hasAttributeValueSelectTarget || !this.hasAttributeKeySelectTarget) return

    const attribute = this.attributeByKey.get(this.attributeKeySelectTarget.value)
    const values = attribute?.values || []
    const optionHtml = [
      '<option value="">Choose value</option>',
      ...values.map((value) => (
        `<option value="${escapeHtml(value.name)}">${escapeHtml(value.name)} (${formatNumber(value.count)})</option>`
      ))
    ].join("")

    this.attributeValueSelectTarget.innerHTML = optionHtml
    this.attributeValueSelectTarget.disabled = values.length === 0
  }

  renderAttributeFilters() {
    const entries = Object.entries(this.attributeFilters)

    if (entries.length === 0) {
      this.attributeFiltersTarget.innerHTML = '<span class="project-insights-filter-empty">No attribute filters</span>'
      return
    }

    this.attributeFiltersTarget.innerHTML = entries.map(([key, value]) => {
      const attribute = this.attributeByKey.get(key) || { label: key }

      return `
        <button type="button"
                class="project-insights-filter-chip"
                data-action="project-insights#removeAttributeFilter"
                data-attribute-key="${escapeHtml(key)}"
                aria-label="Remove ${escapeHtml(attribute.label)} filter">
          <span>${escapeHtml(attribute.label)}=${escapeHtml(value)}</span>
          <span aria-hidden="true">x</span>
        </button>
      `
    }).join("")
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

    this.metricListTarget.innerHTML = groupedMetrics(this.catalog).map((group) => `
      <section class="project-insights-metric-group">
        <div class="project-insights-metric-group-header">
          <div>
            <strong>${escapeHtml(group.label)}</strong>
            <span>${escapeHtml(group.description)}</span>
          </div>
          <span>${formatNumber(group.metrics.length)}</span>
        </div>
        <div class="project-insights-metric-group-list">
          ${group.metrics.map((metric) => this.metricButton(metric)).join("")}
        </div>
      </section>
    `).join("")
  }

  metricButton(metric) {
    const selected = this.selectedMetrics.includes(metric.key)
    const events = metric.events ? `<span>${formatNumber(metric.events)} events</span>` : ""

    return `
      <button type="button"
              class="project-insights-metric ${selected ? "is-selected" : ""}"
              data-action="project-insights#addMetric"
              data-metric-key="${escapeHtml(metric.key)}"
              ${selected ? "disabled" : ""}>
        <span class="project-insights-metric-topline">
          <span class="project-insights-metric-main">
            <strong>${escapeHtml(metric.label)}</strong>
            <span>${escapeHtml(metric.description || metric.source || "")}</span>
          </span>
          <span class="project-insights-metric-action">${selected ? "Added" : "Add"}</span>
        </span>
        <span class="project-insights-metric-meta">
          <span>${escapeHtml(metric.source || "Metric")}</span>
          <span>${escapeHtml(metric.unit || "count")}</span>
          ${events}
        </span>
      </button>
    `
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
    this.summaryTarget.innerHTML = this.summaryCell(summary.events, "Events", "All matching signals") +
      this.summaryCell(summary.errors, "Errors", "Health signals") +
      this.summaryCell(summary.transactions, "Transactions", "Performance spans") +
      this.summaryCell(summary.metrics, "Metrics", "Custom measurements") +
      this.summaryCell(summary.check_ins, "Check-ins", "Monitors and jobs")
  }

  summaryCell(value, label, detail) {
    return `
      <div class="project-insights-summary-cell">
        <strong>${formatNumber(value)}</strong>
        <span>${escapeHtml(label)}</span>
        <small>${escapeHtml(detail)}</small>
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
          name: "count/value",
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

    this.recentEventsTarget.innerHTML = events.map((event) => {
      const attributes = (event.attributes || []).map((attribute) => (
        `<span>${escapeHtml(attribute.label)}=${escapeHtml(attribute.value)}</span>`
      )).join("")

      return `
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
              ${attributes}
            </div>
          </div>
        </div>
      `
    }).join("")
  }

  scheduleRefresh() {
    clearInterval(this.refreshTimer)

    if (this.chartsReady && this.refreshSeconds > 0) {
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
        attributeFilters: this.attributeFilters,
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
    Object.values(this.charts || {}).forEach((chart) => {
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
    if (!this.chartsReady) return

    cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = requestAnimationFrame(() => {
      Object.values(this.charts || {}).forEach((chart) => chart.resize())
    })
  }
}

function normalizeAttributeFilters(filters) {
  if (!filters || typeof filters !== "object" || Array.isArray(filters)) return {}

  return Object.entries(filters).reduce((normalized, [key, value]) => {
    if (!key || value === undefined || value === null || value === "") return normalized

    normalized[String(key)] = String(value)
    return normalized
  }, {})
}

function attributeFiltersFromServer(filters) {
  if (!Array.isArray(filters)) return null

  return filters.reduce((normalized, filter) => {
    if (!filter?.key || !filter?.value) return normalized

    normalized[String(filter.key)] = String(filter.value)
    return normalized
  }, {})
}

function groupedMetrics(metrics) {
  const groups = new Map()

  metrics.forEach((metric) => {
    const key = metric.category || "other"
    const fallback = METRIC_CATEGORY_COPY.other
    const copy = METRIC_CATEGORY_COPY[key] || fallback

    if (!groups.has(key)) {
      groups.set(key, {
        key,
        label: metric.category_label || copy.label,
        description: copy.description,
        metrics: []
      })
    }

    groups.get(key).metrics.push(metric)
  })

  return Array.from(groups.values()).sort((left, right) => {
    const leftIndex = METRIC_CATEGORY_ORDER.indexOf(left.key)
    const rightIndex = METRIC_CATEGORY_ORDER.indexOf(right.key)

    return categorySortIndex(leftIndex) - categorySortIndex(rightIndex) || left.label.localeCompare(right.label)
  })
}

function categorySortIndex(index) {
  return index === -1 ? METRIC_CATEGORY_ORDER.length : index
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
  const formatted = new Intl.NumberFormat(undefined, { maximumFractionDigits: unit === "count" ? 0 : 2 }).format(number)

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
