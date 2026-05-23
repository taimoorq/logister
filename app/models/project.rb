class Project < ApplicationRecord
  DEFAULT_PUBLIC_API_RATE_LIMIT_REQUESTS = 1_200
  DEFAULT_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS = 60
  DEFAULT_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS = 120
  MIN_PUBLIC_API_RATE_LIMIT_REQUESTS = 1
  MAX_PUBLIC_API_RATE_LIMIT_REQUESTS = 10_000_000
  MIN_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS = 1
  MAX_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS = 86_400

  belongs_to :user
  has_many :api_keys, dependent: :destroy
  has_many :ingest_events, dependent: :destroy
  has_many :trace_spans, dependent: :destroy
  has_many :error_groups, dependent: :destroy
  has_many :check_in_monitors, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :project_notification_preferences, dependent: :destroy
  has_many :email_notification_deliveries, dependent: :destroy
  has_one :retention_policy, class_name: "ProjectRetentionPolicy", dependent: :destroy
  has_many :telemetry_archives, dependent: :destroy
  has_many :members, through: :project_memberships, source: :user

  before_validation :ensure_uuid
  before_validation :normalize_slug

  enum :integration_kind, {
    ruby: "ruby",
    cfml: "cfml",
    javascript: "javascript",
    python: "python",
    dotnet: "dotnet",
    http_api: "http_api"
  }, default: :ruby, validate: true, prefix: :integration

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }
  validates :uuid, presence: true, uniqueness: true
  validates :public_api_rate_limit_requests_override,
            :public_api_auth_failure_rate_limit_requests_override,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_PUBLIC_API_RATE_LIMIT_REQUESTS,
              less_than_or_equal_to: MAX_PUBLIC_API_RATE_LIMIT_REQUESTS
            },
            allow_nil: true
  validates :public_api_rate_limit_period_seconds_override,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS,
              less_than_or_equal_to: MAX_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS
            },
            allow_nil: true

  def to_param
    uuid
  end

  def self.accessible_to(user)
    return none unless user

    shared_project_ids = ProjectMembership.where(user_id: user.id).select(:project_id)
    where(user_id: user.id).or(where(id: shared_project_ids))
  end

  def owned_by?(viewer)
    user_id == viewer.id
  end

  def archived?
    archived_at.present?
  end

  def archive!
    archive_time = Time.current

    transaction do
      update!(archived_at: archive_time)
      api_keys.active.update_all(revoked_at: archive_time, updated_at: archive_time)
    end
  end

  def restore!
    update!(archived_at: nil)
  end

  def notification_recipients
    User.where(id: assignable_user_ids).distinct
  end

  def assignable_users
    User.where(id: assignable_user_ids).order(:email)
  end

  def assignable_user?(user)
    return false unless user

    assignable_user_ids.include?(user.id)
  end

  def assignable_user_ids
    @assignable_user_ids ||= [ user_id, *project_memberships.pluck(:user_id) ].uniq
  end

  def integration_label
    {
      "ruby" => "Ruby gem",
      "cfml" => "CFML",
      "javascript" => "JavaScript / TypeScript",
      "python" => "Python",
      "dotnet" => ".NET / ASP.NET Core",
      "http_api" => "Manual / HTTP API"
    }.fetch(integration_kind, integration_kind.to_s.humanize)
  end

  def public_api_rate_limit_requests_effective(default)
    public_api_rate_limit_requests_override || default
  end

  def public_api_rate_limit_period_seconds_effective(default)
    public_api_rate_limit_period_seconds_override || default
  end

  def public_api_auth_failure_rate_limit_requests_effective(default)
    public_api_auth_failure_rate_limit_requests_override || default
  end

  def self.integration_options
    [
      [ "Ruby gem", "ruby" ],
      [ ".NET / ASP.NET Core (logister-dotnet)", "dotnet" ],
      [ "CFML", "cfml" ],
      [ "JavaScript / TypeScript (logister-js)", "javascript" ],
      [ "Python (logister-python)", "python" ],
      [ "Manual / HTTP API (custom client)", "http_api" ]
    ]
  end

  def self.default_public_api_rate_limit_requests
    positive_integer_logister_config(:public_api_rate_limit_requests, DEFAULT_PUBLIC_API_RATE_LIMIT_REQUESTS)
  end

  def self.default_public_api_rate_limit_period_seconds
    positive_integer_logister_config(:public_api_rate_limit_period_seconds, DEFAULT_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS)
  end

  def self.default_public_api_auth_failure_rate_limit_requests
    positive_integer_logister_config(
      :public_api_auth_failure_rate_limit_requests,
      DEFAULT_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS
    )
  end

  # Stats for project index: recent event volume, activity volume, open error groups,
  # total error groups, and 7-day raw event trend per project.
  def self.stats_for(project_ids)
    return {} if project_ids.blank?

    stats = project_ids.index_with do
      { total_events: 0, activity_events: 0, open_groups: 0, all_groups: 0, latest_event_at: nil, trend: Array.new(7, 0) }
    end
    project_error_groups = ErrorGroup.where(project_id: project_ids)
    project_events = IngestEvent.where(project_id: project_ids)
    trend_dates = 7.times.map { |i| Date.current - (6 - i) }
    recent_events = project_events.where("occurred_at >= ?", trend_dates.first.beginning_of_day)

    project_error_groups.group(:project_id).count.each do |pid, count|
      stats[pid][:all_groups] = count
    end

    project_error_groups.unresolved.group(:project_id).count.each do |pid, count|
      stats[pid][:open_groups] = count
    end

    recent_events.where.not(event_type: IngestEvent.event_types[:error]).group(:project_id).count.each do |pid, count|
      stats[pid][:activity_events] = count
    end

    latest_event_at_by_project(project_ids).each do |pid, occurred_at|
      stats[pid][:latest_event_at] = occurred_at
    end

    recent_events
      .group(:project_id, "DATE(occurred_at)")
      .count
      .each do |(pid, date), count|
        idx = trend_dates.index(date.to_date)
        next unless idx

        stats[pid][:trend][idx] = count
        stats[pid][:total_events] += count
      end

    stats
  end

  def self.latest_event_at_by_project(project_ids)
    ids = Array(project_ids).filter_map { |project_id| Integer(project_id, exception: false) }.uniq
    return {} if ids.blank?

    sql = sanitize_sql_array([
      <<~SQL.squish,
        SELECT requested_projects.project_id, latest_events.occurred_at
        FROM unnest(ARRAY[?]::bigint[]) AS requested_projects(project_id)
        LEFT JOIN LATERAL (
          SELECT occurred_at
          FROM ingest_events
          WHERE ingest_events.project_id = requested_projects.project_id
          ORDER BY occurred_at DESC
          LIMIT 1
        ) latest_events ON TRUE
      SQL
      ids
    ])

    connection.exec_query(sql).each_with_object({}) do |row, latest_events|
      occurred_at = row["occurred_at"]
      next if occurred_at.blank?

      latest_events[row["project_id"].to_i] = occurred_at
    end
  end

  private

  def self.positive_integer_logister_config(name, default)
    value = Rails.application.config.x.logister.public_send(name)
    value.to_i.positive? ? value.to_i : default
  rescue NoMethodError
    default
  end
  private_class_method :positive_integer_logister_config

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_slug
    base = slug.presence || name
    self.slug = base.to_s.parameterize
  end
end
