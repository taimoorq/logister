class ProjectMembership < ApplicationRecord
  ROLE_LABELS = {
    "viewer" => "Viewer",
    "admin" => "Admin"
  }.freeze

  belongs_to :project
  belongs_to :user

  enum :role, { viewer: 0, admin: 1 }, default: :viewer, validate: true

  before_validation :ensure_uuid
  after_destroy :clear_assigned_error_groups

  validates :uuid, presence: true, uniqueness: true
  validates :user_id, uniqueness: { scope: :project_id }

  def to_param
    uuid
  end

  def self.role_options
    roles.keys.map { |role| [ ROLE_LABELS.fetch(role), role ] }
  end

  def self.normalize_role(value)
    value.to_s.presence_in(roles.keys) || "viewer"
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def clear_assigned_error_groups
    update_time = Time.current

    project.error_groups.where(assigned_user_id: user_id).update_all(
      assigned_user_id: nil,
      assigned_by_user_id: nil,
      assigned_at: nil,
      updated_at: update_time
    )

    project.error_groups.where(assigned_by_user_id: user_id).update_all(
      assigned_by_user_id: nil,
      updated_at: update_time
    )
  end
end
