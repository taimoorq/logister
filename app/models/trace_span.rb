class TraceSpan < ApplicationRecord
  belongs_to :project
  belongs_to :api_key

  before_validation :ensure_uuid
  before_validation :normalize_kind
  before_validation :derive_ended_at

  KINDS = %w[
    app
    browser
    cache
    db
    http
    internal
    queue
    render
    resource
    server
  ].freeze

  ROOT_KINDS = %w[server browser].freeze

  validates :uuid, presence: true, uniqueness: true
  validates :trace_id, :span_id, :name, :kind, :started_at, presence: true
  validates :span_id, uniqueness: { scope: [ :project_id, :trace_id ] }
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }

  scope :recent_roots, ->(since, limit = 50) {
    where("started_at >= ?", since)
      .where(kind: ROOT_KINDS)
      .where(parent_span_id: [ nil, "" ])
      .order(duration_ms: :desc, started_at: :desc)
      .limit(limit)
  }

  def to_param
    uuid
  end

  def route_name
    context_value("route").presence ||
      context_value("http.route").presence ||
      context_value("transaction_name").presence ||
      name
  end

  def request_id
    context_value("request_id").presence || context_value("requestId").presence
  end

  def context_value(key)
    return unless context.is_a?(Hash)

    context[key] || context[key.to_sym]
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_kind
    self.kind = kind.to_s.underscore.presence || "internal"
    self.kind = "internal" unless KINDS.include?(kind)
  end

  def derive_ended_at
    return if ended_at.present? || started_at.blank?

    self.ended_at = started_at + (duration_ms.to_f / 1000.0)
  end
end
