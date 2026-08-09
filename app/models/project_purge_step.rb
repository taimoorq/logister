# frozen_string_literal: true

class ProjectPurgeStep < ApplicationRecord
  STATUSES = %w[pending running awaiting_external completed skipped failed].freeze
  TERMINAL_STATUSES = %w[completed skipped].freeze

  belongs_to :project_purge, inverse_of: :steps

  validates :store_name, inclusion: { in: ProjectPurge::STORE_ORDER }
  validates :store_name, uniqueness: { scope: :project_purge_id }
  validates :position, uniqueness: { scope: :project_purge_id }
  validates :status, inclusion: { in: STATUSES }
  validates :position, :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :position_matches_store_order

  def terminal?
    status.in?(TERMINAL_STATUSES)
  end

  private

  def position_matches_store_order
    expected_position = ProjectPurge::STORE_ORDER.index(store_name)
    return if expected_position.nil? || position == expected_position

    errors.add(:position, "must be #{expected_position} for #{store_name}")
  end
end
