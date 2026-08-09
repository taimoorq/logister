# frozen_string_literal: true

class ResolvedNavigation < Data.define(:primary_pages, :secondary_pages, :current_page)
  def initialize(primary_pages:, secondary_pages:, current_page:)
    super(
      primary_pages: primary_pages.freeze,
      secondary_pages: secondary_pages.freeze,
      current_page: current_page
    )
    freeze
  end

  def secondary_active?
    secondary_pages.any? do |page|
      page == current_page || page.key == current_page&.active_parent_key
    end
  end
end
