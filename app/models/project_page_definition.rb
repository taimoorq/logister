# frozen_string_literal: true

class ProjectPageDefinition < Data.define(
  :key,
  :route_key,
  :active_parent_key,
  :label,
  :header_label,
  :description,
  :icon_key,
  :navigation_group,
  :menu_group,
  :order,
  :core
)
  NAVIGATION_GROUPS = %i[primary secondary hidden].freeze

  def initialize(**attributes)
    super(**attributes)
    freeze
  end

  def primary?
    navigation_group == :primary
  end

  def secondary?
    navigation_group == :secondary
  end

  def hidden?
    navigation_group == :hidden
  end

  def core?
    core
  end
end
