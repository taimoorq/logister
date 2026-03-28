class IngestEvent < ApplicationRecord
  belongs_to :project
  belongs_to :api_key
  belongs_to :error_group, optional: true
  has_one    :error_occurrence, dependent: :destroy

  before_validation :ensure_uuid

  enum :event_type, { error: 0, metric: 1, transaction: 2, log: 3, check_in: 4 }, validate: true, scopes: false

  validates :uuid, presence: true, uniqueness: true
  validates :message, presence: true
  validates :occurred_at, presence: true

  def to_param
    uuid
  end

  scope :db_queries, -> { where(event_type: :metric, message: "db.query") }
  scope :transactions, -> { where(event_type: :transaction) }
  scope :logs, -> { where(event_type: :log) }
  scope :check_ins, -> { where(event_type: :check_in) }
  scope :recent_db_queries, ->(since, limit = 300) {
    db_queries.where("occurred_at >= ?", since).order(occurred_at: :desc).limit(limit)
  }
  scope :recent_transactions, ->(since, limit = 300) {
    transactions.where("occurred_at >= ?", since).order(occurred_at: :desc).limit(limit)
  }
  scope :released, -> {
    where("COALESCE(context->>'release', '') <> ''")
  }

  # Duration in ms from event context (for db.query metrics).
  def self.duration_ms(event)
    return 0.0 unless event

    value = context_value(event, "duration_ms")
    value = context_value(event, "durationMs") if value.blank?
    value.to_f
  end

  def self.environment(event, default = "production")
    context_value(event, "environment").presence || default
  end

  def self.release(event)
    context_value(event, "release").to_s.presence
  end

  def self.transaction_name(event)
    context_value(event, "transaction_name").presence ||
      context_value(event, "transactionName").presence
  end

  def self.trace_id(event)
    context_value(event, "trace_id").presence ||
      context_value(event, "traceId").presence ||
      nested_context_value(event, "trace", "traceId").presence
  end

  def self.request_id(event)
    context_value(event, "request_id").presence ||
      context_value(event, "requestId").presence ||
      nested_context_value(event, "trace", "requestId").presence
  end

  def self.session_id(event)
    context_value(event, "session_id").presence || context_value(event, "sessionId").presence
  end

  def self.user_identifier(event)
    context_value(event, "user_id").presence ||
      context_value(event, "userId").presence ||
      nested_context_value(event, "user", "id").presence
  end

  def self.released_error_groups(project, lookback: 30.days, limit: 6)
    since = lookback.is_a?(ActiveSupport::Duration) ? lookback.ago : lookback
    releases = released.where(project: project).where("occurred_at >= ?", since)
                       .group(Arel.sql("context->>'release'"))
                       .maximum(:occurred_at)
                       .sort_by { |_rel, seen_at| seen_at || Time.zone.at(0) }
                       .reverse
                       .first(limit)

    releases.map do |(release_name, last_seen_at)|
      events_scope = where(project: project).where("context->>'release' = ?", release_name)
      {
        release: release_name,
        last_seen_at: last_seen_at,
        total_events: events_scope.count,
        error_events: events_scope.where(event_type: :error).count,
        introduced_issues: project.error_groups.where(introduced_in_release: release_name).count,
        regressed_issues: project.error_groups.where(regressed_in_release: release_name).count
      }
    end
  end

  def self.transaction_stats(project, since: 24.hours.ago, apdex_threshold_ms: 300.0)
    events = recent_transactions(since, 2000).where(project: project).to_a
    return { count: 0, throughput_per_minute: 0.0, p50_ms: 0.0, p95_ms: 0.0, error_rate: 0.0, apdex: 0.0 } if events.empty?

    durations = events.map { |event| duration_ms(event) }.select(&:positive?).sort
    p50_index = [ (durations.length * 0.50).ceil - 1, 0 ].max
    p95_index = [ (durations.length * 0.95).ceil - 1, 0 ].max
    threshold = apdex_threshold_ms.to_f.positive? ? apdex_threshold_ms.to_f : 300.0

    errored_count = events.count do |event|
      event.level.to_s.in?(%w[error fatal]) || context_value(event, "status").to_i >= 500
    end

    satisfied = events.count { |event| duration_ms(event) <= threshold }
    tolerating = events.count { |event| duration_ms(event) > threshold && duration_ms(event) <= (threshold * 4.0) }
    apdex = ((satisfied + (tolerating * 0.5)) / events.length.to_f).round(3)

    {
      count: events.length,
      throughput_per_minute: (events.length / 1440.0).round(3),
      p50_ms: durations[p50_index].to_f.round(2),
      p95_ms: durations[p95_index].to_f.round(2),
      error_rate: (errored_count / events.length.to_f).round(3),
      apdex: apdex
    }
  end

  def self.slow_transactions_with_errors(project, since: 24.hours.ago, limit: 20)
    tx_events = recent_transactions(since, 3000).where(project: project).to_a
    return [] if tx_events.empty?

    error_by_tx_name = where(project: project, event_type: :error)
      .where("occurred_at >= ?", since)
      .group_by { |event| transaction_name(event).to_s }

    tx_events
      .sort_by { |event| -duration_ms(event) }
      .first(limit)
      .map do |event|
        name = transaction_name(event).to_s
        related = error_by_tx_name[name] || []
        {
          event: event,
          duration_ms: duration_ms(event).round(2),
          transaction_name: name.presence || "(unnamed transaction)",
          related_error_count: related.length,
          related_error_event: related.max_by(&:occurred_at)
        }
      end
  end

  def self.related_logs(project:, event:, window: 5.minutes, limit: 50)
    trace = trace_id(event)
    request = request_id(event)
    session = session_id(event)
    user = user_identifier(event)
    return [] if [ trace, request, session, user ].all?(&:blank?)

    start_time = (event.occurred_at || Time.current) - window
    end_time = (event.occurred_at || Time.current) + window

    candidates = logs.where(project: project).where(occurred_at: start_time..end_time)
                     .order(occurred_at: :desc).limit(limit * 4).to_a

    candidates.select do |log_event|
      matches = []
      matches << (trace.present? && trace_id(log_event) == trace)
      matches << (request.present? && request_id(log_event) == request)
      matches << (session.present? && session_id(log_event) == session)
      matches << (user.present? && user_identifier(log_event) == user)
      matches.any?
    end.first(limit)
  end

  # Aggregate stats from a list of db.query events: count, avg_ms, p95_ms.
  def self.db_stats_from_events(events)
    durations = events.map { |e| duration_ms(e) }.select(&:positive?)
    return { count: 0, avg_ms: 0.0, p95_ms: 0.0 } if durations.empty?

    sorted = durations.sort
    p95_index = [ (sorted.length * 0.95).ceil - 1, 0 ].max
    {
      count: durations.length,
      avg_ms: (durations.sum / durations.length).round(2),
      p95_ms: sorted[p95_index].round(2)
    }
  end

  # Build dashboard error view hashes from a list of error events (e.g. last 7 days).
  def self.dashboard_error_views(events)
    grouped = events.group_by do |event|
      [ event.project_id, event.fingerprint.presence || event.message.to_s.lines.first.to_s.strip.presence || event.uuid ]
    end

    project_views = grouped.map do |(_, _fingerprint), grouped_events|
      latest = grouped_events.max_by { |e| e.occurred_at || Time.zone.at(0) }
      project = latest.project
      trend_points = 7.times.map do |index|
        date = Date.current - (6 - index)
        grouped_events.count { |e| e.occurred_at&.to_date == date }
      end
      ctx = latest.context.is_a?(Hash) ? latest.context : {}
      stage = ctx["environment"].presence || ctx[:environment].presence || "production"

      {
        fingerprint: latest.fingerprint.presence || latest.uuid,
        project: project,
        latest_event: latest,
        title: latest.message.to_s.lines.first.to_s.strip.presence || "Untitled error",
        events_count: grouped_events.length,
        trend: trend_points,
        stage: stage
      }
    end

    project_views
      .group_by { |view| view[:project] }
      .map do |project, views|
        sorted_views = views.sort_by { |view| view[:latest_event].occurred_at || Time.zone.at(0) }.reverse

        {
          project: project,
          latest_event: sorted_views.first[:latest_event],
          events_count: sorted_views.sum { |view| view[:events_count] },
          error_views: sorted_views
        }
      end
      .sort_by { |project_view| project_view[:latest_event].occurred_at || Time.zone.at(0) }
      .reverse
      .first(6)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def self.context_hash(event)
    event.context.is_a?(Hash) ? event.context : {}
  end

  def self.context_value(event, key)
    ctx = context_hash(event)
    value = ctx[key]
    value = ctx[key.to_sym] if value.blank?
    value
  end

  def self.nested_context_value(event, *keys)
    current = context_hash(event)
    keys.each do |key|
      return nil unless current.is_a?(Hash)

      current = current[key] || current[key.to_sym]
    end
    current
  end
end
