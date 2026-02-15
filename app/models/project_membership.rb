class ProjectMembership < ApplicationRecord
  belongs_to :project
  belongs_to :user

  enum :role, { viewer: 0 }, default: :viewer, validate: true

  before_validation :ensure_uuid

  validates :uuid, presence: true, uniqueness: true
  validates :user_id, uniqueness: { scope: :project_id }

  def to_param
    uuid
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
