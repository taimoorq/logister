class ProjectNotificationPreference < ApplicationRecord
  DIGEST_FREQUENCIES = %w[none daily weekly].freeze
  WORKFLOW_MODES = %w[off assigned_to_me all_project].freeze
  FILTER_ALL = "all"
  STATUS_FILTERS = %w[all unresolved closed].freeze
  MIN_THRESHOLD = 1
  MAX_THRESHOLD = 1_000_000

  belongs_to :project
  belongs_to :user

  before_validation :ensure_uuid
  before_validation :normalize_values

  validates :uuid, presence: true, uniqueness: true
  validates :user_id, uniqueness: { scope: :project_id }
  validates :digest_frequency, inclusion: { in: DIGEST_FREQUENCIES }
  validates :workflow_mode, inclusion: { in: WORKFLOW_MODES }
  validates :status_filter, inclusion: { in: STATUS_FILTERS }
  validates :digest_send_hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
  validates :frequent_error_threshold_count,
            :frequent_error_window_minutes,
            :project_spike_threshold_count,
            :project_spike_window_minutes,
            :performance_p95_threshold_ms,
            numericality: { only_integer: true, greater_than_or_equal_to: MIN_THRESHOLD, less_than_or_equal_to: MAX_THRESHOLD }
  validates :immediate_email_limit_per_hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000 }
  validates :quiet_hours_start,
            :quiet_hours_end,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
  validates :time_zone, presence: true
  validate :time_zone_is_known

  scope :digest_enabled, -> { where(digest_frequency: %w[daily weekly]) }
  scope :for_active_projects, -> { joins(:project).merge(Project.active) }

  def self.for(user:, project:)
    find_or_create_by!(user: user, project: project)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def digest_enabled?
    digest_frequency.in?(%w[daily weekly])
  end

  def immediate_email_enabled_for?(kind, error_group: nil, metadata: {}, now: Time.current)
    return false if quiet_hours_active?(now)

    ProjectNotificationPreferenceRules.immediate_email_enabled?(
      self,
      kind,
      error_group: error_group,
      metadata: metadata
    )
  end

  def immediate_rate_limit_available?(kind, now: Time.current)
    limit = immediate_email_limit_per_hour.to_i
    return false if limit.zero?

    EmailNotificationDelivery
      .where(user: user, project: project, notification_kind: kind.to_s, status: %w[sending sent])
      .where("created_at >= ?", now - 1.hour)
      .count < limit
  end

  def quiet_hours_active?(now = Time.current)
    return false unless quiet_hours_enabled?

    zone = ActiveSupport::TimeZone[time_zone] || Time.zone
    hour = now.in_time_zone(zone).hour
    start_hour = quiet_hours_start.to_i
    end_hour = quiet_hours_end.to_i
    return false if start_hour == end_hour

    if start_hour < end_hour
      hour >= start_hour && hour < end_hour
    else
      hour >= start_hour || hour < end_hour
    end
  end

  def due_digest_window(now = Time.current)
    return nil unless digest_enabled?

    zone = ActiveSupport::TimeZone[time_zone] || Time.zone
    local_now = now.in_time_zone(zone)
    return nil if local_now.hour < digest_send_hour

    case digest_frequency
    when "daily"
      period_end = local_now.beginning_of_day
      [ period_end - 1.day, period_end ]
    when "weekly"
      return nil unless local_now.monday?

      period_end = local_now.beginning_of_day
      [ period_end - 7.days, period_end ]
    end
  end

  def unsubscribe_token
    signed_id(purpose: :notification_unsubscribe)
  end

  def unsubscribe_from_project_email!
    update!(
      first_occurrence_enabled: false,
      regression_enabled: false,
      frequent_error_enabled: false,
      milestone_alerts_enabled: false,
      workflow_mode: "off",
      monitor_alerts_enabled: false,
      project_spike_enabled: false,
      performance_alerts_enabled: false,
      release_notifications_enabled: false,
      usage_notifications_enabled: false,
      retention_notifications_enabled: false,
      digest_frequency: "none"
    )
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_values
    self.digest_frequency = digest_frequency.to_s.presence_in(DIGEST_FREQUENCIES) || "none"
    self.workflow_mode = workflow_mode.to_s.presence_in(WORKFLOW_MODES) || "assigned_to_me"
    self.digest_send_hour = digest_send_hour.to_i
    self.frequent_error_threshold_count = frequent_error_threshold_count.to_i
    self.frequent_error_window_minutes = frequent_error_window_minutes.to_i
    self.project_spike_threshold_count = project_spike_threshold_count.to_i
    self.project_spike_window_minutes = project_spike_window_minutes.to_i
    self.performance_p95_threshold_ms = performance_p95_threshold_ms.to_i
    self.immediate_email_limit_per_hour = immediate_email_limit_per_hour.to_i
    self.quiet_hours_start = quiet_hours_start.to_i
    self.quiet_hours_end = quiet_hours_end.to_i
    self.environment_filter = normalized_filter(environment_filter)
    self.severity_filter = normalized_filter(severity_filter)
    self.status_filter = status_filter.to_s.presence_in(STATUS_FILTERS) || "unresolved"
    self.time_zone = time_zone.to_s.presence || "UTC"
  end

  def time_zone_is_known
    return if ActiveSupport::TimeZone[time_zone]

    errors.add(:time_zone, "is not supported")
  end

  def normalized_filter(value)
    value.to_s.strip.presence || FILTER_ALL
  end
end
