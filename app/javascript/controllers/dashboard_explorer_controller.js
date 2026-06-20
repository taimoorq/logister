import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"
import { EVENT_COLORS } from "charts/telemetry_timeline"

const FALLBACK_COLORS = ["#2563eb", "#059669", "#ef4444", "#8b5cf6", "#d97706", "#0f766e", "#475569"]

export default class extends Controller {
  static targets = [
    "timelineChart",
    "eventTypeChart",
    "projectChart",
    "environmentChart",
    "summary",
    "filters",
    "openEventsLink",
    "openProjectLink",
    "resetButton"
  ]
  static values = {
    payload: Object
  }

  connect() {
    this.payload = this.readPayload()
    this.filters = { eventType: null, projectId: null, environment: null, occurredOn: null }
    this.eventTypes = this.payload.event_types || []
    this.projects = this.payload.projects || []
    this.projectById = new Map(this.projects.map((project) => [String(project.id), project]))
    this.typeLabelByKey = new Map(this.eventTypes.map((eventType) => [eventType.key, eventType.label]))
    this.overviewElement = this.element.closest(".dashboard-overview-layout")
    this.charts = {}
    this.resizeHandler = () => this.queueResize()
    this.beforeCacheHandler = () => this.beforeCache()

    if (this.isTurboPreview()) return

    this.initializeCharts()
    this.renderShell()
    this.fetchData()
    window.addEventListener("resize", this.resizeHandler)
    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)

    if ("ResizeObserver" in window) {
      this.resizeObserver = new ResizeObserver(() => this.queueResize())
      this.resizeObserver.observe(this.element)
      this.timelineChartTargets.forEach((target) => this.resizeObserver.observe(target))
      this.eventTypeChartTargets.forEach((target) => this.resizeObserver.observe(target))
      this.projectChartTargets.forEach((target) => this.resizeObserver.observe(target))
      this.environmentChartTargets.forEach((target) => this.resizeObserver.observe(target))
    }

    this.syncOverviewHeight()
  }

  disconnect() {
    this.abortController?.abort()
    window.removeEventListener("resize", this.resizeHandler)
    document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
    this.resizeObserver?.disconnect()
    this.clearOverviewHeight()
    cancelAnimationFrame(this.resizeFrame)
    this.teardownCharts()
  }

  beforeCache() {
    this.abortController?.abort()
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    this.clearOverviewHeight()
    cancelAnimationFrame(this.resizeFrame)
    this.teardownCharts({ clear: true })
  }

  resetFilters(event) {
    event?.preventDefault()
    this.filters = { eventType: null, projectId: null, environment: null, occurredOn: null }
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
    if (this.hasTimelineChartTarget) this.charts.timeline = this.initializeChart(this.timelineChartTarget)
    if (this.hasEventTypeChartTarget) this.charts.eventTypes = this.initializeChart(this.eventTypeChartTarget)
    if (this.hasProjectChartTarget) this.charts.projects = this.initializeChart(this.projectChartTarget)
    if (this.hasEnvironmentChartTarget) this.charts.environments = this.initializeChart(this.environmentChartTarget)

    this.charts.timeline?.on("click", (params) => this.toggleFilter("occurredOn", params.data?.filterValue))
    this.charts.eventTypes?.on("click", (params) => this.toggleFilter("eventType", params.data?.filterValue))
    this.charts.projects?.on("click", (params) => this.toggleFilter("projectId", params.data?.filterValue))
    this.charts.environments?.on("click", (params) => this.toggleFilter("environment", params.data?.filterValue))
  }

  initializeChart(target) {
    if (!target) return null

    echarts.getInstanceByDom(target)?.dispose()

    return echarts.init(target, null, { renderer: "canvas" })
  }

  renderShell() {
    this.renderSummary({ events: 0, active_projects: 0, environments: 0 })
    this.renderFilterChips()
    this.renderOpenEventsLink()
    this.renderOpenProjectLink()
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
        this.currentExplorerData = data
        this.renderData(data)
      })
      .catch((error) => {
        if (error.name === "AbortError") return

        console.warn("[Logister] Dashboard explorer failed to render", error)
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
    if (this.filters.occurredOn) url.searchParams.set("occurred_on", this.filters.occurredOn)

    return url
  }

  eventsUrl() {
    const url = new URL(this.payload.events_endpoint || "/dashboard/events", window.location.origin)

    if (this.filters.eventType) url.searchParams.set("event_type", this.filters.eventType)
    if (this.filters.projectId) url.searchParams.set("project_id", this.filters.projectId)
    if (this.filters.environment) url.searchParams.set("environment", this.filters.environment)
    if (this.filters.occurredOn) url.searchParams.set("occurred_on", this.filters.occurredOn)

    return url
  }

  renderData(data) {
    this.renderSummary(data.totals || { events: 0, active_projects: 0, environments: 0 })
    this.renderFilterChips()
    this.renderOpenEventsLink(data)
    this.renderOpenProjectLink(data)
    this.renderTimeline(data)
    this.renderEventTypes(data)
    this.renderProjects(data)
    this.renderEnvironments(data)
    this.resetButtonTarget.disabled = !this.hasActiveFilters()
    this.syncOverviewHeight()
  }

  renderError() {
    this.summaryTarget.innerHTML = `
      <span><strong>--</strong><span>Events</span></span>
      <span><strong>--</strong><span>Active apps</span></span>
      <span><strong>--</strong><span>Environments</span></span>
    `
    this.renderOpenEventsLink()
    this.renderOpenProjectLink()
    this.syncOverviewHeight()
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
      chips.push(this.filterChip("projectId", this.projectById.get(String(this.filters.projectId))?.name || "Project"))
    }

    if (this.filters.environment) {
      chips.push(this.filterChip("environment", this.filters.environment))
    }

    if (this.filters.occurredOn) {
      chips.push(this.filterChip("occurredOn", shortDateLabel(this.filters.occurredOn)))
    }

    this.filtersTarget.innerHTML = chips.length > 0
      ? chips.join("")
      : '<span class="dashboard-explorer-filter-empty">No filters applied</span>'
  }

  renderOpenEventsLink(data = null) {
    const eventCount = Number(data?.totals?.events) || 0

    this.openEventsLinkTarget.href = data?.events_url || this.eventsUrl()
    this.openEventsLinkTarget.textContent = eventCount > 0
      ? `Open ${formatNumber(eventCount)} matching events`
      : "Open matching events"
  }

  renderOpenProjectLink(data = null) {
    if (!this.hasOpenProjectLinkTarget) return

    const project = this.projectForInboxLink(data)

    if (!project?.url) {
      this.openProjectLinkTarget.hidden = true
      this.openProjectLinkTarget.removeAttribute("href")
      this.openProjectLinkTarget.textContent = "Open project"
      this.openProjectLinkTarget.removeAttribute("aria-label")
      return
    }

    this.openProjectLinkTarget.hidden = false
    this.openProjectLinkTarget.href = project.url
    this.openProjectLinkTarget.textContent = "Open project"
    this.openProjectLinkTarget.setAttribute("aria-label", `Open ${project.name} project`)
  }

  projectForInboxLink(data = null) {
    if (this.filters.projectId) return this.projectById.get(String(this.filters.projectId))

    const projectRows = data?.projects || []
    if (projectRows.length !== 1) return null

    const project = projectRows[0]
    return this.projectById.get(String(project.id)) || project
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
    const counts = new Map(rows.map((row) => [timelineKey(row.day, row.event_type), Number(row.count) || 0]))
    const series = this.eventTypes.map((eventType) => ({
      name: eventType.label,
      type: "line",
      smooth: true,
      symbolSize: 5,
      emphasis: { focus: "series" },
      color: EVENT_COLORS[eventType.key],
      data: days.map((day) => ({
        value: counts.get(timelineKey(day, eventType.key)) || 0,
        filterValue: day
      }))
    }))
    const hasData = series.some((line) => line.data.some((point) => point.value > 0))

    this.setChartOption(this.charts.timeline, {
      aria: { enabled: true },
      color: this.chartColors(),
      graphic: emptyGraphic(!hasData, "No events in this slice"),
      grid: { left: 40, right: 16, top: 20, bottom: 28 },
      tooltip: { trigger: "axis", formatter: tooltipFormatter },
      xAxis: { type: "category", boundaryGap: false, data: days.map(shortDateLabel), axisTick: { show: false } },
      yAxis: { type: "value", minInterval: 1, axisLabel: { formatter: compactNumber } },
      series
    })
  }

  renderEventTypes(data) {
    const items = data.event_types || []
    const chartData = items.map((eventType) => ({
      name: eventType.label,
      value: eventType.count,
      filterValue: eventType.key,
      itemStyle: { color: EVENT_COLORS[eventType.key] }
    })).filter((item) => item.value > 0)

    this.setChartOption(this.charts.eventTypes, {
      aria: { enabled: true },
      graphic: emptyGraphic(chartData.length === 0, "No event types"),
      grid: { left: 8, right: 16, top: 8, bottom: 8, containLabel: true },
      tooltip: { trigger: "item", formatter: itemTooltipFormatter },
      xAxis: { type: "value", minInterval: 1, axisLabel: { formatter: compactNumber } },
      yAxis: { type: "category", data: chartData.map((item) => item.name), inverse: true, axisTick: { show: false } },
      series: [{ type: "bar", barWidth: 12, data: chartData }]
    })
  }

  renderProjects(data) {
    const chartData = (data.projects || []).map((project) => ({
      name: project.name,
      value: project.count,
      filterValue: String(project.id),
      openErrors: project.open_errors || 0,
      itemStyle: { color: project.open_errors > 0 ? "#ef4444" : "#2563eb" }
    })).sort((a, b) => b.value - a.value).slice(0, 8)

    this.setChartOption(this.charts.projects, {
      aria: { enabled: true },
      graphic: emptyGraphic(chartData.length === 0, "No app activity"),
      grid: { left: 8, right: 18, top: 8, bottom: 8, containLabel: true },
      tooltip: {
        trigger: "item",
        formatter: (params) => `${escapeHtml(params.name)}<br>${formatNumber(params.value)} events<br>${formatNumber(params.data.openErrors)} open errors`
      },
      xAxis: { type: "value", minInterval: 1, axisLabel: { formatter: compactNumber } },
      yAxis: { type: "category", data: chartData.map((item) => item.name), inverse: true, axisTick: { show: false } },
      series: [{ type: "bar", barWidth: 12, data: chartData }]
    })
  }

  renderEnvironments(data) {
    const chartData = (data.environments || []).map((environment) => ({
      name: environment.name,
      value: environment.count,
      filterValue: environment.name
    }))

    this.setChartOption(this.charts.environments, {
      aria: { enabled: true },
      color: FALLBACK_COLORS,
      graphic: emptyGraphic(chartData.length === 0, "No environments"),
      tooltip: { trigger: "item", formatter: itemTooltipFormatter },
      series: [{
        type: "pie",
        radius: ["48%", "78%"],
        center: ["50%", "50%"],
        avoidLabelOverlap: true,
        label: { formatter: "{b}", overflow: "truncate", width: 90 },
        data: chartData
      }]
    })
  }

  timelineDays(data) {
    if (Array.isArray(data.days) && data.days.length > 0) return data.days

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
    Object.values(this.charts).forEach((chart) => chart?.resize())
  }

  queueResize() {
    cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = requestAnimationFrame(() => {
      this.resizeCharts()
      this.syncOverviewHeight()
    })
  }

  syncOverviewHeight() {
    if (!this.overviewElement) return

    const height = Math.ceil(this.element.getBoundingClientRect().height)
    if (height > 0) this.overviewElement.style.setProperty("--dashboard-explorer-height", `${height}px`)
  }

  clearOverviewHeight() {
    this.overviewElement?.style.removeProperty("--dashboard-explorer-height")
  }

  setChartOption(chart, option) {
    if (!chart) return

    chart.setOption(option, true)
  }

  setLoading(loading) {
    Object.values(this.charts).forEach((chart) => {
      if (!chart) return

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

  isTurboPreview() {
    return document.documentElement.hasAttribute("data-turbo-preview")
  }

  teardownCharts({ clear = false } = {}) {
    Object.values(this.charts || {}).forEach((chart) => chart?.dispose())
    this.charts = {}

    if (clear) this.chartTargets().forEach((target) => target.replaceChildren())
  }

  chartTargets() {
    return [
      ...this.timelineChartTargets,
      ...this.eventTypeChartTargets,
      ...this.projectChartTargets,
      ...this.environmentChartTargets
    ]
  }
}

function timelineKey(day, eventType) {
  return `${day}::${eventType}`
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
