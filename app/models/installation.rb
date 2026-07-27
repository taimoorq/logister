# frozen_string_literal: true

class Installation < ApplicationRecord
  SINGLETON_KEY = "primary"

  belongs_to :claimed_by_user, class_name: "User", optional: true
  belongs_to :self_monitoring_project, class_name: "Project", optional: true
  belongs_to :self_monitoring_api_key, class_name: "ApiKey", optional: true
  has_many :installation_steps, dependent: :destroy

  validates :singleton_key, presence: true, uniqueness: true
  validate :self_monitoring_destination_is_valid

  def self.current
    find_or_create_by!(singleton_key: SINGLETON_KEY)
  end

  def self.current_if_available
    find_by(singleton_key: SINGLETON_KEY)
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def self.first_admin_setup_available?
    ENV["LOGISTER_SETUP_TOKEN"].to_s.present? && !current_if_available&.claimed?
  end

  def claimed?
    claimed_at.present? && claimed_by_user_id.present?
  end

  def complete?
    completed_at.present?
  end

  def claim!(user)
    with_lock do
      return self if claimed?

      update!(claimed_by_user: user, claimed_at: Time.current)
    end
    self
  end

  def step_for(key)
    installation_steps.find_or_initialize_by(key: key.to_s)
  end

  def required_steps_verified?
    InstanceConfiguration::Registry.required_section_keys.all? do |key|
      step = installation_steps.find_by(key: key)
      step&.verified? && step.configuration_fingerprint == InstanceConfiguration.fingerprint(key)
    end
  end

  def complete!
    raise ActiveRecord::RecordInvalid, self unless required_steps_verified?

    update!(completed_at: Time.current, onboarding_required: false)
  end

  private

  def self_monitoring_destination_is_valid
    if self_monitoring_project
      errors.add(:self_monitoring_project, "must use the Ruby integration") unless self_monitoring_project.integration_ruby?
      errors.add(:self_monitoring_project, "must be active") if self_monitoring_project.archived?
    end

    return unless self_monitoring_api_key

    errors.add(:self_monitoring_api_key, "must be active") unless self_monitoring_api_key.active?
    if self_monitoring_project.nil?
      errors.add(:self_monitoring_api_key, "requires a self-monitoring project")
    elsif self_monitoring_api_key.project_id != self_monitoring_project_id
      errors.add(:self_monitoring_api_key, "must belong to the self-monitoring project")
    end
  end
end
