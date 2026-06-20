# frozen_string_literal: true

class ProjectDeployment < ApplicationRecord
  PROVIDERS = {
    github: "github"
  }.freeze
  SOURCES = {
    api: "api",
    telemetry: "telemetry",
    manual: "manual"
  }.freeze
  SHA_PATTERN = /\A[0-9a-f]{7,40}\z/i

  belongs_to :project
  belongs_to :project_source_repository, optional: true
  belongs_to :github_repository, optional: true

  before_validation :apply_repository
  before_validation :normalize_fields
  after_create_commit :enqueue_release_notification

  validates :uuid, presence: true, uniqueness: true
  validates :provider, inclusion: { in: PROVIDERS.values }
  validates :repository_full_name, :environment, :release, :commit_sha, :source, presence: true
  validates :source, inclusion: { in: SOURCES.values }
  validates :repository_full_name, format: {
    with: /\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/,
    message: "must look like owner/repository"
  }
  validates :commit_sha, format: { with: SHA_PATTERN, message: "must be a 7 to 40 character commit SHA" }
  validates :release, uniqueness: {
    scope: [ :project_id, :repository_full_name, :environment ],
    message: "has already been indexed for this repository and environment"
  }

  scope :newest_first, -> { order(Arel.sql("COALESCE(deployed_at, updated_at) DESC"), id: :desc) }

  def self.resolve_commit(project:, repository:, release:, environment:)
    release = release.to_s.strip.presence
    repository_full_name = normalize_repository_full_name(repository_full_name_for(repository))
    environment = normalize_environment(environment)
    return nil if project.blank? || repository_full_name.blank? || release.blank?

    candidates = where(project: project, repository_full_name: repository_full_name, release: release)
    candidates.find_by(environment: environment)&.commit_sha ||
      candidates.find_by(environment: "production")&.commit_sha ||
      candidates.newest_first.first&.commit_sha
  end

  def self.normalize_repository_full_name(value)
    normalized = value.to_s.strip
    normalized = normalized.sub(%r{\Ahttps://github\.com/}i, "")
    normalized = normalized.sub(%r{\Agit@github\.com:}i, "")
    normalized = normalized.delete_prefix("/")
    normalized = normalized.delete_suffix(".git")
    normalized.split("/").first(2).join("/").presence
  end

  def self.normalize_environment(value)
    value.to_s.strip.presence || "production"
  end

  def self.valid_commit_sha?(value)
    value.to_s.match?(SHA_PATTERN)
  end

  def to_param
    uuid
  end

  def short_commit_sha
    commit_sha.to_s.first(7)
  end

  def github_commit_url
    return if repository_full_name.blank? || commit_sha.blank?

    "#{Logister::GithubAppConfig.web_url}/#{repository_full_name}/commit/#{commit_sha}"
  end

  def pull_request_number
    metadata_value("pull_request_number")
  end

  def pull_request_url
    metadata_value("pull_request_url").presence || inferred_pull_request_url
  end

  def pull_request_label
    return if pull_request_number.blank?

    "PR ##{pull_request_number}"
  end

  def release_url
    metadata_value("release_url").presence || inferred_release_url
  end

  def release_tag
    metadata_value("release_tag").presence || release
  end

  def compare_url(previous_deployment)
    return if previous_deployment.blank?
    return unless previous_deployment.repository_full_name == repository_full_name
    return if previous_deployment.commit_sha.blank? || commit_sha.blank?

    "#{Logister::GithubAppConfig.web_url}/#{repository_full_name}/compare/#{previous_deployment.commit_sha}...#{commit_sha}"
  end

  private

  def self.repository_full_name_for(repository)
    repository.respond_to?(:full_name) ? repository.full_name : repository
  end
  private_class_method :repository_full_name_for

  def apply_repository
    if project_source_repository
      self.provider = PROVIDERS[:github]
      self.github_repository ||= project_source_repository.github_repository
      self.repository_full_name = project_source_repository.full_name if repository_full_name.blank?
    elsif github_repository
      self.provider = PROVIDERS[:github]
      self.repository_full_name = github_repository.full_name if repository_full_name.blank?
    end
  end

  def normalize_fields
    self.uuid ||= SecureRandom.uuid
    self.provider = provider.to_s.strip.presence || PROVIDERS[:github]
    self.repository_full_name = self.class.normalize_repository_full_name(repository_full_name)
    self.environment = self.class.normalize_environment(environment)
    self.release = release.to_s.strip.presence
    self.commit_sha = commit_sha.to_s.strip.downcase.presence
    self.branch = normalize_branch(branch)
    self.source = source.to_s.strip.presence || SOURCES[:api]
    self.metadata = metadata.is_a?(Hash) ? metadata : {}
  end

  def normalize_branch(value)
    value.to_s.strip.delete_prefix("refs/heads/").presence
  end

  def metadata_value(key)
    metadata.is_a?(Hash) ? metadata[key] || metadata[key.to_sym] : nil
  end

  def inferred_pull_request_url
    return if repository_full_name.blank? || pull_request_number.blank?

    "#{Logister::GithubAppConfig.web_url}/#{repository_full_name}/pull/#{pull_request_number}"
  end

  def inferred_release_url
    return if repository_full_name.blank? || release_tag.blank?

    "#{Logister::GithubAppConfig.web_url}/#{repository_full_name}/releases/tag/#{ERB::Util.url_encode(release_tag)}"
  end

  def enqueue_release_notification
    ProjectReleaseNotificationJob.perform_later(id)
  end
end
