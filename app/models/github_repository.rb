# frozen_string_literal: true

class GithubRepository < ApplicationRecord
  belongs_to :github_installation
  has_many :project_source_repositories, dependent: :nullify
  has_many :project_deployments, dependent: :nullify

  before_validation :normalize_fields

  validates :external_id, presence: true, uniqueness: true
  validates :full_name, :owner_name, :repo_name, presence: true
  validate :full_name_matches_owner_and_repo

  scope :active, -> { where(active: true, archived: false) }
  scope :for_picker, -> { active.includes(:github_installation).order(:full_name) }
  scope :visible_to, lambda { |user|
    user ? active.joins(:github_installation).where(github_installations: { installed_by_id: user.id }) : none
  }
  scope :available_for_project, lambda { |project|
    if project
      active
        .joins(github_installation: :project_github_installations)
        .merge(GithubInstallation.active)
        .where(project_github_installations: { project_id: project.id })
    else
      none
    end
  }

  def available?
    active? && !archived? && github_installation&.available?
  end

  private

  def normalize_fields
    self.full_name = full_name.to_s.strip.delete_suffix(".git").presence
    self.owner_name, self.repo_name = full_name.to_s.split("/", 2) if full_name.present?
    self.default_branch = default_branch.to_s.strip.presence
    self.html_url = html_url.to_s.strip.presence
    self.permissions = permissions.is_a?(Hash) ? permissions : {}
    self.metadata = metadata.is_a?(Hash) ? metadata : {}
  end

  def full_name_matches_owner_and_repo
    return if full_name.blank?
    return if full_name.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z})

    errors.add(:full_name, "must look like owner/repository")
  end
end
