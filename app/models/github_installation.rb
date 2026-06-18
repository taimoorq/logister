# frozen_string_literal: true

class GithubInstallation < ApplicationRecord
  belongs_to :installed_by, class_name: "User", optional: true
  has_many :source_repositories, class_name: "ProjectSourceRepository", dependent: :nullify
  has_many :github_repositories, dependent: :destroy

  before_validation :ensure_uuid
  before_validation :normalize_fields

  validates :uuid, presence: true, uniqueness: true
  validates :installation_id, presence: true, uniqueness: true
  validates :account_login, presence: true

  scope :active, -> { where(active: true, suspended_at: nil) }
  scope :visible_to, ->(user) { user ? where(installed_by: user) : none }

  def to_param
    uuid
  end

  def available?
    active? && suspended_at.blank?
  end

  def active_repository_count
    if github_repositories.loaded?
      github_repositories.count { |repository| repository.active? && !repository.archived? }
    else
      github_repositories.active.count
    end
  end

  def permission_at_least?(name, level)
    permission_level(permissions[name.to_s]) >= permission_level(level)
  end

  def last_repository_synced_at
    if github_repositories.loaded?
      github_repositories.filter_map(&:last_synced_at).max
    else
      github_repositories.maximum(:last_synced_at)
    end
  end

  private

  def permission_level(value)
    case value.to_s
    when "write", "admin" then 2
    when "read" then 1
    else 0
    end
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_fields
    self.account_login = account_login.to_s.strip.presence
    self.account_type = account_type.to_s.strip.presence
    self.repository_selection = repository_selection.to_s.strip.presence
    self.permissions = permissions.is_a?(Hash) ? permissions : {}
    self.events = events.is_a?(Array) ? events : []
  end
end
