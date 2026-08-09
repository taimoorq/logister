# frozen_string_literal: true

require "set"

class ProjectExperienceDefinition < Data.define(
  :key,
  :family_key,
  :version,
  :profile_class_name,
  :product_capabilities,
  :capability_loader_class_name
)
  DEFINITIONS = [
    new(
      key: :server,
      family_key: :server_application,
      version: 1,
      profile_class_name: "ProjectExperiences::Generic",
      product_capabilities: Set.new.freeze,
      capability_loader_class_name: "ProjectCapabilityLoaders::Static"
    ).freeze,
    new(
      key: :edge,
      family_key: :edge_site,
      version: 1,
      profile_class_name: "ProjectExperiences::Generic",
      product_capabilities: Set.new.freeze,
      capability_loader_class_name: "ProjectCapabilityLoaders::Static"
    ).freeze,
    new(
      key: :android,
      family_key: :mobile_application,
      version: 1,
      profile_class_name: "ProjectExperiences::Android",
      product_capabilities: Set.new(%i[
        mobile release_aware device_context structured_stacktrace
        session_health stack_mapping distribution_store
      ]).freeze,
      capability_loader_class_name: "ProjectCapabilityLoaders::Android"
    ).freeze,
    new(
      key: :ios,
      family_key: :mobile_application,
      version: 1,
      profile_class_name: "ProjectExperiences::Ios",
      product_capabilities: Set.new(%i[
        mobile release_aware device_context structured_stacktrace
        apple_diagnostics session_health symbol_artifacts distribution_store
      ]).freeze,
      capability_loader_class_name: "ProjectCapabilityLoaders::Ios"
    ).freeze,
    new(
      key: :custom,
      family_key: :custom_telemetry,
      version: 1,
      profile_class_name: "ProjectExperiences::Generic",
      product_capabilities: Set.new.freeze,
      capability_loader_class_name: "ProjectCapabilityLoaders::Static"
    ).freeze
  ].freeze

  BY_KEY = DEFINITIONS.to_h { |definition| [ definition.key, definition ] }.freeze

  def profile_class
    profile_class_name.constantize
  end

  def capability_loader_class
    capability_loader_class_name.constantize
  end

  def pages
    ProjectPageCatalog.fetch(key)
  end

  class << self
    def all
      DEFINITIONS
    end

    def keys
      BY_KEY.keys
    end

    def fetch(key)
      BY_KEY.fetch(key.to_sym)
    end

    def validate!
      duplicate_keys = DEFINITIONS.map(&:key).tally.select { |_key, count| count > 1 }.keys
      raise ArgumentError, "Duplicate project experience keys: #{duplicate_keys.join(', ')}" if duplicate_keys.any?

      DEFINITIONS.each do |definition|
        raise ArgumentError, "Project experience key cannot be blank" if definition.key.blank?
        raise ArgumentError, "Project experience #{definition.key} must have a family" if definition.family_key.blank?
        raise ArgumentError, "Project experience #{definition.key} must have a positive version" unless definition.version.to_i.positive?
        raise ArgumentError, "Project experience #{definition.key} must have a profile class" if definition.profile_class_name.blank?
        raise ArgumentError, "Project experience #{definition.key} capabilities must be frozen" unless definition.product_capabilities.frozen?
        raise ArgumentError, "Project experience #{definition.key} must have a capability loader" if definition.capability_loader_class_name.blank?
        ProjectPageCatalog.validate!(definition.key)
      end

      true
    end
  end
end
