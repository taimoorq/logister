# frozen_string_literal: true

module Admin::Installation::SettingsSupport
  extend ActiveSupport::Concern

  private

  def set_section
    @section = InstanceConfiguration::Registry.section!(params[:section])
    @definitions = InstanceConfiguration::Registry.definitions_for(@section.key)
  rescue KeyError
    raise ActiveRecord::RecordNotFound
  end

  def set_installation
    @installation = Installation.current
    @installation.claim!(current_user)
    @step = @installation.installation_steps.find_or_create_by!(key: @section.key)
  end

  def prepare_view(form_values: nil)
    @entries = InstanceConfiguration.entries_for(@section.key)
    current_fingerprint = InstanceConfiguration.fingerprint(@section.key)
    @step_status = current_step_status(current_fingerprint)
    @form_values = form_values || form_values_from_entries
    keys = @definitions.map(&:key) + [ "section.#{@section.key}" ]
    @changes = InstanceSettingChange.where(key: keys).includes(:actor).order(created_at: :desc).limit(20)
    prepare_observability_context if @section.key == "observability"
    section_index = InstanceConfiguration::Registry.sections.index(@section)
    @next_section = InstanceConfiguration::Registry.sections[section_index + 1]
  end

  def current_step_status(current_fingerprint)
    return "changed" if @step.verified? && @step.configuration_fingerprint != current_fingerprint

    @step.status
  end

  def form_values_from_entries
    @entries.to_h do |entry|
      value = if entry.secret?
        nil
      elsif entry.environment_override?
        entry.saved_value
      else
        entry.saved_value.nil? ? entry.effective_value : entry.saved_value
      end
      [ entry.key, value ]
    end
  end

  def prepare_observability_context
    @self_monitoring_status = Logister::SelfMonitoringStatus.new
    @self_monitoring_projects = Project.active.where(integration_kind: "ruby").order(:name).to_a
  end

  def setting_values
    raw_params = params[:settings].is_a?(ActionController::Parameters) ? params[:settings] : ActionController::Parameters.new
    raw = raw_params.permit(@definitions.map(&:key)).to_h
    @definitions.each_with_object({}) do |definition, values|
      values[definition.key] = raw[definition.key] if raw.key?(definition.key)
    end
  end

  def requesting_clickhouse_reads?(values)
    @section.key == "clickhouse" && values["clickhouse.mode"] == "read_preferred"
  end

  def verified_for?(fingerprint)
    @step.verified? && @step.configuration_fingerprint == fingerprint
  end

  def verified_for_clickhouse_reads?(fingerprint)
    verified_for?(fingerprint) && @step.details["ready_for_reads"] == true
  end

  def unsaved_email_delivery_test?(fingerprint)
    @section.key == "email" && params[:test_recipient].to_s.strip.present? && fingerprint != InstanceConfiguration.fingerprint("email")
  end
end
