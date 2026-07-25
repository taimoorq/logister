# frozen_string_literal: true

class InstallationStep < ApplicationRecord
  STATUSES = %w[pending configured verified skipped].freeze

  belongs_to :installation
  belongs_to :last_verified_by_user, class_name: "User", optional: true

  validates :key, presence: true, uniqueness: { scope: :installation_id }
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  def mark_configured!(fingerprint:)
    update!(
      status: "configured",
      configuration_fingerprint: fingerprint,
      last_verified_at: nil,
      last_verified_by_user: nil,
      details: {}
    )
  end

  def mark_verified!(fingerprint:, user:, details: {})
    update!(
      status: "verified",
      configuration_fingerprint: fingerprint,
      last_verified_at: Time.current,
      last_verified_by_user: user,
      details: details
    )
  end

  def mark_skipped!(user:)
    update!(
      status: "skipped",
      configuration_fingerprint: nil,
      last_verified_at: Time.current,
      last_verified_by_user: user,
      details: {}
    )
  end
end
