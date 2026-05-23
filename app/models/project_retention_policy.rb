class ProjectRetentionPolicy < ApplicationRecord
  DEFAULT_HOT_RETENTION_DAYS = 30
  DEFAULT_TRACE_RETENTION_DAYS = 30
  DEFAULT_ERROR_RETENTION_DAYS = nil
  RETENTION_DAY_OPTIONS = [ 7, 14, 30, 60, 90, 180, 365 ].freeze
  MIN_RETENTION_DAYS = 1
  MAX_RETENTION_DAYS = 3_650

  belongs_to :project

  validates :hot_retention_days,
            :trace_retention_days,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: MIN_RETENTION_DAYS, less_than_or_equal_to: MAX_RETENTION_DAYS }
  validates :error_retention_days,
            numericality: { only_integer: true, greater_than_or_equal_to: MIN_RETENTION_DAYS, less_than_or_equal_to: MAX_RETENTION_DAYS },
            allow_nil: true
  validate :archive_before_delete_requires_archive

  def self.for(project:)
    project.retention_policy || project.create_retention_policy!
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def error_retention_forever?
    error_retention_days.blank?
  end

  private

  def archive_before_delete_requires_archive
    return unless archive_before_delete? && !archive_enabled?

    errors.add(:archive_before_delete, "requires retention exports to be enabled")
  end
end
