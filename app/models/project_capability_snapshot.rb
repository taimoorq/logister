# frozen_string_literal: true

class ProjectCapabilitySnapshot
  attr_reader :project, :experience_definition, :statuses

  def self.for(project)
    new(project: project)
  end

  def initialize(project:)
    @project = project
    @experience_definition = ProjectExperience.definition_for(project.integration_kind)
    static_statuses = experience_definition.product_capabilities.to_h do |key|
      [ key, CapabilityStatus.new(key: key, state: :available, provenance: :product_definition) ]
    end
    dynamic_statuses = experience_definition.capability_loader_class.new(project).call
    @statuses = static_statuses.merge(dynamic_statuses).freeze
  end

  def status(key)
    statuses.fetch(key.to_sym) do
      CapabilityStatus.new(
        key: key,
        state: :unsupported,
        provenance: :product_definition,
        reason: "This project experience does not support the capability."
      )
    end
  end

  def supports?(key)
    status(key).supported?
  end

  def usable?(key)
    status(key).usable?
  end
end
