# frozen_string_literal: true

class Admin::InstallationController < Admin::BaseController
  OPTIONAL_GROUPS = [
    {
      label: "Invite and notify people",
      description: "Add outbound email before other users depend on account recovery or project notifications.",
      keys: %w[email]
    },
    {
      label: "Scale and retain telemetry",
      description: "Add analytics capacity or archive older telemetry outside the primary database.",
      keys: %w[clickhouse archive_storage]
    },
    {
      label: "Connect source and protect access",
      description: "Link private source repositories and add bot protection to public account forms.",
      keys: %w[github authentication]
    },
    {
      label: "Operate the public instance",
      description: "Configure consent-aware public analytics, self-monitoring, and release checks.",
      keys: %w[public_site observability]
    }
  ].freeze

  before_action :set_installation

  def show
    ensure_steps
    @sections = InstanceConfiguration::Registry.sections
    @steps_by_key = @installation.installation_steps.index_by(&:key)
    @section_states = @sections.to_h do |section|
      step = @steps_by_key.fetch(section.key)
      stale = step.verified? && step.configuration_fingerprint != InstanceConfiguration.fingerprint(section.key)
      [ section.key, { step: step, status: stale ? "changed" : step.status } ]
    end
    @required_sections = @sections.select(&:required?)
    @required_verified_count = @required_sections.count { |section| @section_states.fetch(section.key).fetch(:status) == "verified" }
    @next_required_section = @required_sections.find { |section| @section_states.fetch(section.key).fetch(:status) != "verified" }
    sections_by_key = @sections.index_by(&:key)
    @optional_groups = OPTIONAL_GROUPS.filter_map do |group|
      group.merge(sections: group.fetch(:keys).filter_map { |key| sections_by_key[key] })
    end
    @environment_override_count = InstanceConfiguration::Registry.definitions.count do |definition|
      InstanceConfiguration.entry(definition.key).environment_override?
    end
  end

  def complete
    if @installation.required_steps_verified?
      @installation.complete!
      redirect_to dashboard_path, notice: "Installation checks completed. You can return to Admin → Installation whenever the stack changes."
    else
      redirect_to admin_installation_path, alert: "Verify the required General and Redis & jobs sections before completing setup."
    end
  end

  private

  def set_installation
    @installation = Installation.current
    @installation.claim!(current_user)
  end

  def ensure_steps
    InstanceConfiguration::Registry.sections.each do |section|
      @installation.installation_steps.find_or_create_by!(key: section.key)
    end
  end
end
