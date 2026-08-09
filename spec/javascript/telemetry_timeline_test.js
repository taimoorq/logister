import assert from "node:assert/strict"
import test from "node:test"

import { metricTimelineOption } from "../../app/javascript/charts/telemetry_timeline.js"

test("metric legends show the metric description on hover", () => {
  const option = metricTimelineOption({
    labels: ["12:00"],
    metricSeries: [{
      label: "P95 transaction duration",
      description: "95th percentile transaction duration from Performance.",
      unit: "ms",
      data: [{ value: 120 }]
    }]
  })

  assert.equal(option.legend.tooltip.show, true)
  assert.equal(
    option.legend.tooltip.formatter({ name: "P95 transaction duration" }),
    "<strong>P95 transaction duration</strong><br>95th percentile transaction duration from Performance."
  )
})

test("metric legend descriptions are escaped before rendering", () => {
  const option = metricTimelineOption({
    metricSeries: [{
      label: "Custom <metric>",
      description: "Average <script>alert('x')</script> value.",
      unit: "value",
      data: []
    }]
  })

  assert.equal(
    option.legend.tooltip.formatter({ name: "Custom <metric>" }),
    "<strong>Custom &lt;metric&gt;</strong><br>Average &lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; value."
  )
})
