# frozen_string_literal: true

class ProjectInboxOccurrenceScope
  TIME_RANGES = {
    "24h" => 24.hours,
    "7d" => 7.days,
    "30d" => 30.days,
    "90d" => 90.days
  }.freeze

  attr_reader :project, :dimensions

  def initialize(project:, dimensions: {})
    @project = project
    @dimensions = dimensions.to_h.stringify_keys.compact_blank
  end

  def relation(group_ids: nil)
    scope = ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })
    scope = scope.where(error_group_id: group_ids) if group_ids

    dimensions.each do |key, value|
      scope = apply_dimension(scope, key, value)
    end

    scope
  end

  def since
    TIME_RANGES[dimensions["time_range"]]&.ago
  end

  private

  def apply_dimension(scope, key, value)
    case key
    when "time_range"
      since ? scope.where("error_occurrences.occurred_at >= ?", since) : scope
    when "foreground"
      scope.where(foreground: ActiveModel::Type::Boolean.new.cast(value))
    when "mechanism"
      scope.where(mechanism: value)
    when "release"
      scope.where(release: value)
    else
      scope.where("error_occurrences.dimensions ->> ? = ?", key, value)
    end
  end
end
