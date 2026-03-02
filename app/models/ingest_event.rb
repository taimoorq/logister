class IngestEvent < ApplicationRecord
  belongs_to :project
  belongs_to :api_key
  belongs_to :error_group, optional: true
  has_one    :error_occurrence, dependent: :destroy

  before_validation :ensure_uuid

  enum :event_type, { error: 0, metric: 1 }, validate: true

  validates :uuid, presence: true, uniqueness: true
  validates :message, presence: true
  validates :occurred_at, presence: true

  def to_param
    uuid
  end

  scope :db_queries, -> { metric.where(message: "db.query") }
  scope :recent_db_queries, ->(since, limit = 300) {
    db_queries.where("occurred_at >= ?", since).order(occurred_at: :desc).limit(limit)
  }

  # Duration in ms from event context (for db.query metrics).
  def self.duration_ms(event)
    return 0.0 unless event

    ctx = event.context.is_a?(Hash) ? event.context : {}
    (ctx["duration_ms"] || ctx[:duration_ms]).to_f
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

    grouped.map do |(_, _fingerprint), grouped_events|
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
    end.sort_by { |v| v[:latest_event].occurred_at || Time.zone.at(0) }.reverse.first(6)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
