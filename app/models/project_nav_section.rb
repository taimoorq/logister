# frozen_string_literal: true

# A project tab. Every experience shares the same sections, in the same order;
# the pages a section opens come from the experience's page catalog.
class ProjectNavSection < Data.define(:key, :label, :icon_key, :order, :pinned)
  ALL = [
    new(key: :overview, label: "Overview", icon_key: :home, order: 10, pinned: false),
    new(key: :issues, label: "Issues", icon_key: :inbox, order: 20, pinned: false),
    new(key: :performance, label: "Performance", icon_key: :performance, order: 30, pinned: false),
    new(key: :releases, label: "Releases", icon_key: :deployments, order: 40, pinned: false),
    new(key: :explore, label: "Explore", icon_key: :search, order: 50, pinned: false),
    new(key: :monitors, label: "Monitors", icon_key: :monitors, order: 60, pinned: false),
    new(key: :settings, label: "Settings", icon_key: :settings, order: 90, pinned: true)
  ].freeze

  BY_KEY = ALL.to_h { |section| [ section.key, section ] }.freeze
  KEYS = BY_KEY.keys.freeze

  def initialize(**attributes)
    super
    freeze
  end

  class << self
    def fetch(key)
      BY_KEY.fetch(key.to_sym)
    end

    def key?(key)
      BY_KEY.key?(key.to_sym)
    end
  end
end
