# frozen_string_literal: true

# The navigation for one project page: one tab per visible section, plus the
# views of the current section when it has more than one.
class ResolvedNavigation < Data.define(:tabs, :current_page)
  Tab = Data.define(:section, :pages) do
    def key = section.key
    def label = section.label
    def icon_key = section.icon_key
    def pinned? = section.pinned

    # The tab opens the section's first navigable page.
    def entry_page = pages.find(&:view?) || pages.find { |page| !page.hidden? }

    def views = pages.select(&:view?)
  end

  def initialize(tabs:, current_page:)
    super(tabs: tabs.freeze, current_page: current_page)
    freeze
  end

  def current_tab
    return unless current_page

    tabs.find { |tab| tab.key == current_page.section_key }
  end

  def current?(tab)
    tab.key == current_page&.section_key
  end

  def current_section_label
    current_tab&.label
  end

  # Views are only worth showing when the section offers a choice.
  def views
    views = current_tab&.views || []
    views.size > 1 ? views : []
  end

  def view_current?(page)
    current_page&.key == page.key || current_page&.parent_key == page.key
  end
end
