module DashboardHelper
  EVENT_TYPE_LABELS = {
    "error" => "Errors",
    "log" => "Logs",
    "metric" => "Metrics",
    "transaction" => "Transactions",
    "check_in" => "Check-ins"
  }.freeze

  EVENT_TYPE_BADGE_CLASSES = {
    "error" => "dashboard-event-badge dashboard-event-badge-error",
    "log" => "dashboard-event-badge dashboard-event-badge-log",
    "metric" => "dashboard-event-badge dashboard-event-badge-metric",
    "transaction" => "dashboard-event-badge dashboard-event-badge-transaction",
    "check_in" => "dashboard-event-badge dashboard-event-badge-check-in"
  }.freeze

  def dashboard_event_type_label(event_type)
    EVENT_TYPE_LABELS.fetch(event_type.to_s, event_type.to_s.humanize)
  end

  def dashboard_event_badge_class(event_type)
    EVENT_TYPE_BADGE_CLASSES.fetch(event_type.to_s, "dashboard-event-badge")
  end

  def dashboard_metric_state_class(count)
    count.to_i.positive? ? "dashboard-metric-state-attention" : "dashboard-metric-state-ok"
  end
end
