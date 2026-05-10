class ProjectNotificationPreference < ApplicationRecord
  DIGEST_FREQUENCIES = %w[none daily weekly].freeze

  belongs_to :project
  belongs_to :user

  before_validation :ensure_uuid
  before_validation :normalize_values

  validates :uuid, presence: true, uniqueness: true
  validates :user_id, uniqueness: { scope: :project_id }
  validates :digest_frequency, inclusion: { in: DIGEST_FREQUENCIES }
  validates :digest_send_hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
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
      digest_frequency: "none"
    )
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_values
    self.digest_frequency = digest_frequency.to_s.presence_in(DIGEST_FREQUENCIES) || "none"
    self.digest_send_hour = digest_send_hour.to_i
    self.time_zone = time_zone.to_s.presence || "UTC"
  end

  def time_zone_is_known
    return if ActiveSupport::TimeZone[time_zone]

    errors.add(:time_zone, "is not supported")
  end
end
