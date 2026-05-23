export const EVENT_COLORS = {
  error: "#ef4444",
  log: "#64748b",
  metric: "#8b5cf6",
  transaction: "#059669",
  check_in: "#2563eb"
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

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
