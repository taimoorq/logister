export const EVENT_COLORS = {
  error: "#ef4444",
  log: "#64748b",
  metric: "#8b5cf6",
  transaction: "#059669",
  check_in: "#2563eb"
}

export const SERIES_COLORS = ["#2563eb", "#059669", "#ef4444", "#8b5cf6", "#d97706", "#0f766e", "#475569", "#db2777"]

export function metricTimelineOption({
  labels = [],
  metricSeries = [],
  emptyText = "No values in this slice",
  noSeriesText = "Add a metric to chart",
  includeSliderZoom = true,
  grid = { left: 48, right: 54, top: 42, bottom: 58 }
} = {}) {
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
    color: metric.color || SERIES_COLORS[index % SERIES_COLORS.length],
    data: (metric.data || []).map((point) => Number(point.value) || 0)
  }))
  const hasData = series.some((line) => line.data.some((value) => value > 0))
  const dataZoom = [{ type: "inside", filterMode: "none", throttle: 50 }]

  if (includeSliderZoom) {
    dataZoom.push({
      type: "slider",
      height: 18,
      bottom: 8,
      filterMode: "none",
      borderColor: "#e2e8f0",
      fillerColor: "rgba(37, 99, 235, 0.14)",
      handleStyle: { color: "#2563eb" },
      textStyle: { color: "#64748b" }
    })
  }

  return {
    aria: { enabled: true },
    color: SERIES_COLORS,
    graphic: emptyGraphic(!hasData, series.length > 0 ? emptyText : noSeriesText),
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
    dataZoom,
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
    grid,
    series
  }
}

export function metricSeriesFromEventTimeline({ rows = [], eventTypes = [] } = {}) {
  return eventTypes.map((eventType) => ({
    key: eventType.key,
    label: eventType.label,
    unit: "count",
    color: EVENT_COLORS[eventType.key] || eventType.color || "#2563eb",
    data: rows.map((row) => ({
      timestamp: row.timestamp,
      value: Number(row[eventType.key]) || 0
    }))
  }))
}

export function emptyChartOption(text) {
  return {
    graphic: emptyGraphic(true, text),
    series: []
  }
}

export function telemetryTimelineOption({
  rows = [],
  eventTypes = [],
  labels = null,
  labelFormatter = defaultTimeLabel,
  emptyText = "No telemetry",
  includeDataZoom = false
} = {}) {
  const xAxisLabels = labels || rows.map((row) => labelFormatter(row.timestamp))
  const series = eventTypes.map((eventType) => ({
    name: eventType.label,
    type: "bar",
    stack: "events",
    barMaxWidth: 18,
    emphasis: { focus: "series" },
    itemStyle: { color: EVENT_COLORS[eventType.key] || eventType.color || "#2563eb" },
    data: rows.map((row) => Number(row[eventType.key]) || 0)
  }))
  const hasData = series.some((bar) => bar.data.some((value) => value > 0))
  const option = {
    aria: { enabled: true },
    graphic: emptyGraphic(!hasData, emptyText),
    grid: { left: 42, right: 16, top: 34, bottom: 34 },
    legend: {
      top: 0,
      type: "scroll",
      icon: "roundRect",
      textStyle: { color: "#475569", fontSize: 11 }
    },
    tooltip: { trigger: "axis", formatter: telemetryTooltipFormatter },
    xAxis: {
      type: "category",
      data: xAxisLabels,
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
  }

  if (includeDataZoom) {
    option.dataZoom = [
      { type: "inside", filterMode: "none", throttle: 50 }
    ]
  }

  return option
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

function telemetryTooltipFormatter(params) {
  if (!Array.isArray(params) || params.length === 0) return ""

  const rows = params.filter((item) => Number(item.value) > 0).map((item) => (
    `${item.marker}${escapeHtml(item.seriesName)}: ${formatNumber(item.value)}`
  ))

  return `${escapeHtml(params[0].axisValueLabel || "")}<br>${rows.length > 0 ? rows.join("<br>") : "No telemetry"}`
}

function metricTooltipFormatter(params, definitionsByName) {
  if (!Array.isArray(params) || params.length === 0) return ""

  const rows = params.filter((item) => Number(item.value) > 0).map((item) => {
    const definition = definitionsByName.get(item.seriesName) || {}
    return `${item.marker}${escapeHtml(item.seriesName)}: ${formatValue(item.value, definition.unit)}`
  })

  return `${escapeHtml(params[0].axisValueLabel || "")}<br>${rows.length > 0 ? rows.join("<br>") : "No values"}`
}

function defaultTimeLabel(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  return new Intl.DateTimeFormat(undefined, { hour: "numeric" }).format(date)
}

function formatNumber(value) {
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

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
