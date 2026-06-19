# frozen_string_literal: true

class ProjectGithubInstallation < ApplicationRecord
  belongs_to :project
  belongs_to :github_installation
  belongs_to :linked_by, class_name: "User", optional: true

  before_validation :ensure_uuid

  validates :uuid, presence: true, uniqueness: true
  validates :github_installation_id, uniqueness: { scope: :project_id }

  def to_param
    uuid
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
