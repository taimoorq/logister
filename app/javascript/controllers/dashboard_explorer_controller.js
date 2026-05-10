import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

const EVENT_COLORS = {
  error: "#ef4444",
  log: "#64748b",
  metric: "#8b5cf6",
  transaction: "#059669",
  check_in: "#2563eb"
}

const FALLBACK_COLORS = ["#2563eb", "#059669", "#ef4444", "#8b5cf6", "#d97706", "#0f766e", "#475569"]

export default class extends Controller {
  static targets = [
    "timelineChart",
    "eventTypeChart",
    "projectChart",
    "environmentChart",
    "summary",
    "filters",
    "resetButton"
  ]
  static values = {
    payload: Object
  }

  connect() {
    this.payload = this.readPayload()
    this.filters = { eventType: null, projectId: null, environment: null }
    this.eventTypes = this.payload.event_types || []
    this.projects = this.payload.projects || []
    this.projectById = new Map(this.projects.map((project) => [project.id, project]))
    this.typeLabelByKey = new Map(this.eventTypes.map((eventType) => [eventType.key, eventType.label]))
    this.charts = {}

    this.initializeCharts()
    this.renderShell()
    this.fetchData()
    this.resizeHandler = () => this.resizeCharts()
    window.addEventListener("resize", this.resizeHandler)
  }

  disconnect() {
    this.abortController?.abort()
    window.removeEventListener("resize", this.resizeHandler)
    Object.values(this.charts).forEach((chart) => chart.dispose())
  }

  resetFilters(event) {
    event?.preventDefault()
    this.filters = { eventType: null, projectId: null, environment: null }
    this.renderShell()
    this.fetchData()
  }

  removeFilter(event) {
    event.preventDefault()
    const key = event.currentTarget.dataset.filterKey
    if (!Object.prototype.hasOwnProperty.call(this.filters, key)) return

    this.filters[key] = null
    this.renderShell()
    this.fetchData()
  }

  readPayload() {
    return this.hasPayloadValue ? this.payloadValue : { event_types: [], projects: [] }
  }

  initializeCharts() {
    this.charts.timeline = echarts.init(this.timelineChartTarget, null, { renderer: "canvas" })
    this.charts.eventTypes = echarts.init(this.eventTypeChartTarget, null, { renderer: "canvas" })
    this.charts.projects = echarts.init(this.projectChartTarget, null, { renderer: "canvas" })
    this.charts.environments = echarts.init(this.environmentChartTarget, null, { renderer: "canvas" })

    this.charts.eventTypes.on("click", (params) => this.toggleFilter("eventType", params.data?.filterValue))
    this.charts.projects.on("click", (params) => this.toggleFilter("projectId", params.data?.filterValue))
    this.charts.environments.on("click", (params) => this.toggleFilter("environment", params.data?.filterValue))
  }

  renderShell() {
    this.renderSummary({ events: 0, active_projects: 0, environments: 0 })
    this.renderFilterChips()
    this.resetButtonTarget.disabled = !this.hasActiveFilters()
  }

  fetchData() {
    this.abortController?.abort()
    this.abortController = new AbortController()
    const controller = this.abortController
    this.setLoading(true)

    fetch(this.explorerUrl(), {
      headers: { Accept: "application/json" },
      signal: controller.signal
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Explorer request failed: ${response.status}`)

        return response.json()
      })
      .then((data) => {
        this.data = data
        this.renderData(data)
      })
      .catch((error) => {
        if (error.name === "AbortError") return

        this.renderError()
      })
      .finally(() => {
        if (this.abortController === controller) this.setLoading(false)
      })
  }

  explorerUrl() {
    const url = new URL(this.payload.endpoint || "/dashboard/explorer", window.location.origin)

    if (this.filters.eventType) url.searchParams.set("event_type", this.filters.eventType)
    if (this.filters.projectId) url.searchParams.set("project_id", this.filters.projectId)
    if (this.filters.environment) url.searchParams.set("environment", this.filters.environment)

    return url
  }

  renderData(data) {
    this.renderSummary(data.totals || { events: 0, active_projects: 0, environments: 0 })
    this.renderFilterChips()
    this.renderTimeline(data)
    this.renderEventTypes(data)
    this.renderProjects(data)
    this.renderEnvironments(data)
    this.resetButtonTarget.disabled = !this.hasActiveFilters()
  }

  renderError() {
    this.summaryTarget.innerHTML = `
      <span><strong>--</strong><span>Events</span></span>
      <span><strong>--</strong><span>Active apps</span></span>
      <span><strong>--</strong><span>Environments</span></span>
    `
  }

  toggleFilter(key, value) {
    if (value === undefined || value === null) return

    this.filters[key] = this.filters[key] === value ? null : value
    this.renderShell()
    this.fetchData()
  }

  renderSummary(totals) {
    this.summaryTarget.innerHTML = `
      <span><strong>${formatNumber(totals.events)}</strong><span>Events</span></span>
      <span><strong>${formatNumber(totals.active_projects)}</strong><span>Active apps</span></span>
      <span><strong>${formatNumber(totals.environments)}</strong><span>Environments</span></span>
    `
  }

  renderFilterChips() {
    const chips = []

    if (this.filters.eventType) {
      chips.push(this.filterChip("eventType", this.labelForEventType(this.filters.eventType)))
    }

    if (this.filters.projectId) {
      chips.push(this.filterChip("projectId", this.projectById.get(this.filters.projectId)?.name || "Project"))
    }

    if (this.filters.environment) {
      chips.push(this.filterChip("environment", this.filters.environment))
    }

    this.filtersTarget.innerHTML = chips.length > 0
      ? chips.join("")
      : '<span class="dashboard-explorer-filter-empty">No filters applied</span>'
  }

  filterChip(key, label) {
    return `
      <button type="button" class="dashboard-explorer-filter" data-action="dashboard-explorer#removeFilter" data-filter-key="${key}">
        <span>${escapeHtml(label)}</span>
        <span aria-hidden="true">x</span>
      </button>
    `
  }

  renderTimeline(data) {
    const rows = data.timeline || []
    const days = this.timelineDays(data)
    const series = this.eventTypes.map((eventType) => ({
      name: eventType.label,
      type: "line",
      smooth: true,
      symbolSize: 5,
      emphasis: { focus: "series" },
      color: EVENT_COLORS[eventType.key],
      data: days.map((day) => sum(rows.filter((row) => row.day === day && row.event_type === eventType.key), "count"))
    }))

    this.charts.timeline.setOption({
      aria: { enabled: true },
      color: this.chartColors(),
      grid: { left: 40, right: 16, top: 20, bottom: 28 },
      tooltip: { trigger: "axis", formatter: tooltipFormatter },
      xAxis: { type: "category", boundaryGap: false, data: days.map(shortDateLabel), axisTick: { show: false } },
      yAxis: { type: "value", minInterval: 1, axisLabel: { formatter: compactNumber } },
      series
    }, true)
  }

  renderEventTypes(data) {
    const items = data.event_types || []
    const chartData = items.map((eventType) => ({
      name: eventType.label,
      value: eventType.count,
      filterValue: eventType.key,
      itemStyle: { color: EVENT_COLORS[eventType.key] }
    })).filter((item) => item.value > 0)

    this.charts.eventTypes.setOption({
      aria: { enabled: true },
      grid: { left: 8, right: 16, top: 8, bottom: 8, containLabel: true },
      tooltip: { trigger: "item", formatter: itemTooltipFormatter },
      xAxis: { type: "value", minInterval: 1, axisLabel: { formatter: compactNumber } },
      yAxis: { type: "category", data: chartData.map((item) => item.name), inverse: true, axisTick: { show: false } },
      series: [{ type: "bar", barWidth: 12, data: chartData }]
    }, true)
  }

  renderProjects(data) {
    const chartData = (data.projects || []).map((project) => ({
      name: project.name,
      value: project.count,
      filterValue: project.id,
      openErrors: project.open_errors || 0,
      itemStyle: { color: project.open_errors > 0 ? "#ef4444" : "#2563eb" }
    })).sort((a, b) => b.value - a.value).slice(0, 8)

    this.charts.projects.setOption({
      aria: { enabled: true },
      grid: { left: 8, right: 18, top: 8, bottom: 8, containLabel: true },
      tooltip: {
        trigger: "item",
        formatter: (params) => `${escapeHtml(params.name)}<br>${formatNumber(params.value)} events<br>${formatNumber(params.data.openErrors)} open errors`
      },
      xAxis: { type: "value", minInterval: 1, axisLabel: { formatter: compactNumber } },
      yAxis: { type: "category", data: chartData.map((item) => item.name), inverse: true, axisTick: { show: false } },
      series: [{ type: "bar", barWidth: 12, data: chartData }]
    }, true)
  }

  renderEnvironments(data) {
    const chartData = (data.environments || []).map((environment) => ({
      name: environment.name,
      value: environment.count,
      filterValue: environment.name
    }))

    this.charts.environments.setOption({
      aria: { enabled: true },
      color: FALLBACK_COLORS,
      tooltip: { trigger: "item", formatter: itemTooltipFormatter },
      series: [{
        type: "pie",
        radius: ["48%", "78%"],
        center: ["50%", "50%"],
        avoidLabelOverlap: true,
        label: { formatter: "{b}", overflow: "truncate", width: 90 },
        data: chartData
      }]
    }, true)
  }

  timelineDays(data) {
    const days = Array.from(new Set((data.timeline || []).map((row) => row.day))).sort()
    if (days.length > 0) return days

    const windowDays = data.window_days || this.payload.window_days || 7
    const start = data.window_started_at ? new Date(data.window_started_at) : new Date()

    return Array.from({ length: windowDays }, (_value, index) => {
      const day = new Date(start)
      day.setDate(start.getDate() + index)
      return day.toISOString().slice(0, 10)
    })
  }

  labelForEventType(eventType) {
    return this.typeLabelByKey.get(eventType) || eventType.replace("_", " ")
  }

  hasActiveFilters() {
    return Object.values(this.filters).some((value) => value !== null)
  }

  resizeCharts() {
    Object.values(this.charts).forEach((chart) => chart.resize())
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

  chartColors() {
    return this.eventTypes.map((eventType) => EVENT_COLORS[eventType.key] || "#2563eb")
  }
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + (Number(row[key]) || 0), 0)
}

function formatNumber(value) {
  return new Intl.NumberFormat().format(value || 0)
}

function compactNumber(value) {
  return new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(value || 0)
}

function shortDateLabel(value) {
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(new Date(`${value}T00:00:00`))
}

function tooltipFormatter(params) {
  return params
    .filter((item) => item.value > 0)
    .map((item) => `${escapeHtml(item.seriesName)}: ${formatNumber(item.value)}`)
    .join("<br>")
}

function itemTooltipFormatter(params) {
  return `${escapeHtml(params.name)}<br>${formatNumber(params.value)} events`
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
