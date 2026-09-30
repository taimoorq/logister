# frozen_string_literal: true

# One project page. Every page belongs to a section (a project tab). A page
# with a `view_label` is a selectable view inside its section; a hidden page
# (issue detail, correlations) belongs to a section without being a view, and
# names the page whose view stays highlighted while it is open.
class ProjectPageDefinition < Data.define(
  :key,
  :route_key,
  :section_key,
  :view_label,
  :label,
  :header_label,
  :description,
  :icon_key,
  :hidden,
  :parent_key,
  :order
)
  def initialize(**attributes)
    super(**{ view_label: nil, hidden: false, parent_key: nil }.merge(attributes))
    freeze
  end

  def hidden?
    hidden
  end

  def view?
    !hidden && view_label.present?
  end

  def section
    ProjectNavSection.fetch(section_key)
  end
end
