# frozen_string_literal: true

class ProjectExperience
  REGISTRY = {
    "android" => "ProjectExperiences::Android",
    "ios" => "ProjectExperiences::Ios"
  }.freeze

  class << self
    def for(project)
      profile_class_for(project.integration_kind).new(project)
    end

    def registered_kinds
      Project.integration_kinds.keys
    end

    private

    def profile_class_for(integration_kind)
      REGISTRY.fetch(integration_kind.to_s, "ProjectExperiences::Generic").constantize
    end
  end
end
