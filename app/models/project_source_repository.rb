# frozen_string_literal: true

class ProjectSourceRepository < ApplicationRecord
  PROVIDERS = {
    github: "github"
  }.freeze

  belongs_to :project
  belongs_to :github_installation, optional: true
  belongs_to :github_repository, optional: true
  has_many :deployments, class_name: "ProjectDeployment", dependent: :nullify

  before_validation :ensure_uuid
  before_validation :apply_github_repository
  before_validation :normalize_fields

  enum :provider, PROVIDERS, validate: true, prefix: true

  validates :uuid, presence: true, uniqueness: true
  validates :provider, presence: true
  validates :full_name, presence: true, uniqueness: { scope: [ :project_id, :provider ] }
  validates :owner_name, :repo_name, presence: true
  validate :full_name_matches_owner_and_repo
  validate :roots_are_safe_relative_paths

  scope :enabled, -> { where(enabled: true) }
  scope :github, -> { where(provider: PROVIDERS[:github]) }

  def to_param
    uuid
  end

  def configured?
    enabled? && provider_github? && effective_github_installation&.available? && github_repository_available?
  end

  def effective_github_installation
    github_repository&.github_installation || github_installation
  end

  def github_issue_creation_available?
    configured? && effective_github_installation&.permission_at_least?(:issues, :write)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def apply_github_repository
    return unless github_repository

    self.provider = PROVIDERS[:github]
    self.github_installation ||= github_repository.github_installation
    self.external_id ||= github_repository.external_id
    self.full_name = github_repository.full_name if full_name.blank?
    self.default_branch = github_repository.default_branch if default_branch.blank?
  end

  def normalize_fields
    self.provider = provider.to_s.strip.presence || PROVIDERS[:github]
    self.full_name = normalize_full_name(full_name)
    self.owner_name, self.repo_name = full_name.to_s.split("/", 2) if full_name.present?
    self.default_branch = default_branch.to_s.strip.presence
    self.runtime_root = normalize_root(runtime_root, allow_absolute: true)
    self.source_root = normalize_root(source_root, allow_absolute: false)
    self.metadata = metadata.is_a?(Hash) ? metadata : {}
  end

  def normalize_full_name(value)
    normalized = value.to_s.strip
    normalized = normalized.sub(%r{\Ahttps://github\.com/}i, "")
    normalized = normalized.sub(%r{\Agit@github\.com:}i, "")
    normalized = normalized.delete_prefix("/")
    normalized = normalized.delete_suffix(".git")
    normalized.split("/").first(2).join("/").presence
  end

  def normalize_root(value, allow_absolute:)
    root = value.to_s.strip.tr("\\", "/").presence
    return nil if root.blank?

    root = root.delete_suffix("/")
    root = root.delete_prefix("/") unless allow_absolute
    root.presence
  end

  def full_name_matches_owner_and_repo
    return if full_name.blank?
    return if full_name.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z})

    errors.add(:full_name, "must look like owner/repository")
  end

  def roots_are_safe_relative_paths
    [ [ :source_root, source_root ], [ :runtime_root, runtime_root ] ].each do |attribute, root|
      next if root.blank?
      next unless root.split("/").include?("..")

      errors.add(attribute, "cannot include path traversal")
    end
  end

  def github_repository_available?
    github_repository.blank? || github_repository.available?
  end
end
