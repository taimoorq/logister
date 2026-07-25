# frozen_string_literal: true

class Admin::InstallationController < Admin::BaseController
  before_action :set_installation

  def show
    ensure_steps
    @sections = InstanceConfiguration::Registry.sections
    @steps_by_key = @installation.installation_steps.index_by(&:key)
    @environment_override_count = InstanceConfiguration::Registry.definitions.count do |definition|
      InstanceConfiguration.entry(definition.key).environment_override?
    end
  end

  def complete
    if @installation.required_steps_verified?
      @installation.update!(completed_at: Time.current)
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
