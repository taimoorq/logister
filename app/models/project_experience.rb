# frozen_string_literal: true

class ProjectExperience
  REGISTRY = ProjectIntegrationDefinition.all.to_h do |integration|
    [ integration.key, integration.default_experience_key ]
  end.freeze

  class << self
    def for(project)
      definition_for(project.integration_kind).profile_class.new(project)
    end

    def registered_kinds
      REGISTRY.keys
    end

    def definition_for(integration_kind)
      experience_key = REGISTRY.fetch(integration_kind.to_s)
      ProjectExperienceDefinition.fetch(experience_key)
    end

    def validate_registry!
      ProjectIntegrationDefinition.validate!
      ProjectExperienceDefinition.validate!

      enum_keys = Project.integration_kinds.keys
      missing_keys = enum_keys - registered_kinds
      extra_keys = registered_kinds - enum_keys

      if missing_keys.any? || extra_keys.any?
        raise ArgumentError,
              "Project experience registry mismatch (missing: #{missing_keys.join(', ')}; extra: #{extra_keys.join(', ')})"
      end

      ProjectIntegrationDefinition.all.each do |integration|
        integration.allowed_experience_keys.each { |key| ProjectExperienceDefinition.fetch(key) }
        definition = ProjectExperienceDefinition.fetch(integration.default_experience_key)
        profile_class = definition.profile_class
        capability_loader_class = definition.capability_loader_class

        unless profile_class <= ProjectExperiences::Base
          raise ArgumentError,
                "Project experience #{definition.key} profile must inherit from ProjectExperiences::Base"
        end

        next if capability_loader_class <= ProjectCapabilityLoaders::Static

        raise ArgumentError,
              "Project experience #{definition.key} capability loader must inherit from ProjectCapabilityLoaders::Static"
      end

      true
    end
  end
end
