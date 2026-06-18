# frozen_string_literal: true

class ErrorGroupExternalLink < ApplicationRecord
  PROVIDERS = {
    github: "github"
  }.freeze

  LINK_TYPES = {
    issue: "issue",
    pull_request: "pull_request"
  }.freeze

  belongs_to :project
  belongs_to :error_group
  belongs_to :created_by, class_name: "User", optional: true

  before_validation :ensure_uuid
  before_validation :normalize_fields
  before_validation :apply_github_link_metadata

  enum :provider, PROVIDERS, validate: true, prefix: true
  enum :link_type, LINK_TYPES, validate: true, prefix: true

  validates :uuid, presence: true, uniqueness: true
  validates :provider, :link_type, :url, presence: true
  validates :url, uniqueness: { scope: :error_group_id }
  validate :error_group_matches_project
  validate :github_link_is_issue_or_pull_request

  scope :github, -> { where(provider: PROVIDERS[:github]) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def to_param
    uuid
  end

  def display_label
    title.presence || default_display_label
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_fields
    self.provider = provider.to_s.strip.presence || PROVIDERS[:github]
    self.link_type = link_type.to_s.strip.presence || LINK_TYPES[:issue]
    self.url = url.to_s.strip.presence
    self.title = title.to_s.strip.presence
    self.repository_full_name = repository_full_name.to_s.strip.presence
    self.external_id = external_id.to_s.strip.presence
    self.metadata = metadata.is_a?(Hash) ? metadata : {}
  end

  def apply_github_link_metadata
    return unless provider.to_s == PROVIDERS[:github]
    return if url.blank?

    parsed = Github::ExternalLinkParser.call(url)
    return unless parsed

    self.url = parsed.url
    self.link_type = parsed.link_type
    self.repository_full_name = parsed.repository_full_name
    self.external_id = parsed.external_id
    self.title ||= parsed.title
  end

  def github_link_is_issue_or_pull_request
    return unless provider.to_s == PROVIDERS[:github]
    return if url.blank? || Github::ExternalLinkParser.call(url)

    errors.add(:url, "must be a GitHub issue or pull request URL")
  end

  def error_group_matches_project
    return if error_group.blank? || project.blank? || error_group.project_id == project.id

    errors.add(:error_group, "must belong to the project")
  end

  def default_display_label
    repository = repository_full_name.presence || "GitHub"
    number = external_id.present? ? " ##{external_id}" : ""
    type = link_type_pull_request? ? "PR" : "issue"

    "#{repository} #{type}#{number}"
  end
end
