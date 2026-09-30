# frozen_string_literal: true

# The guided presentation of project creation. It is another way to fill in the
# same form: `POST /projects` stays the one command that creates a project, and
# what has been chosen so far travels in the URL between steps (no server-side
# draft), so Back, refresh and sharing all behave.
module ProjectCreationWizard
  extend ActiveSupport::Concern

  CREATION_STEPS = %w[platform details retention].freeze

  CREATION_STEP_LABELS = {
    "platform" => [ "Platform", "What sends telemetry" ],
    "details" => [ "Name and description", "How your team finds it" ],
    "retention" => [ "Data retention", "How long to keep events" ]
  }.freeze

  DEFAULT_INTEGRATION_KIND = "ruby"

  private

  # Everything a creation step needs to render, from what has been chosen so far.
  def prepare_creation_step(step, project: nil)
    @creation_step = step
    @project = project || current_user.projects.new(creation_attributes)
    @project.integration_kind ||= DEFAULT_INTEGRATION_KIND
    build_default_retention_policy
    load_self_monitoring_creation_context
    @monitor_this_installation = ActiveModel::Type::Boolean.new.cast(params.dig(:project, :monitor_this_installation)) || false
    @carried = carried_creation_values
    @wizard_frame = WizardFrame.new(
      context: "New project",
      detail: "Create: #{CREATION_STEP_LABELS.fetch(step).first}",
      exit_label: "Cancel",
      exit_path: projects_path,
      progress_label: "Create project progress",
      done: CREATION_STEPS.index(step),
      total: CREATION_STEPS.size + 1
    )
  end

  def creation_attributes
    raw = params.fetch(:project, {}).permit(
      :name, :description, :integration_kind,
      retention_policy_attributes: %i[hot_retention_days trace_retention_days error_retention_days archive_enabled archive_before_delete]
    ).to_h
    kind = raw["integration_kind"].presence_in(Project.integration_kinds.keys)
    attributes = raw.slice("name", "description")
    attributes["integration_kind"] = kind if kind
    attributes["retention_policy_attributes"] = raw["retention_policy_attributes"] if raw["retention_policy_attributes"].present?
    attributes
  end

  # Values from earlier steps, as full field names, so a step can carry the ones
  # it does not edit forward as hidden fields.
  def carried_creation_values
    values = {}
    values["project[integration_kind]"] = @project.integration_kind
    values["project[name]"] = @project.name if @project.name.present?
    values["project[description]"] = @project.description if @project.description.present?
    values["project[monitor_this_installation]"] = params.dig(:project, :monitor_this_installation) if params.dig(:project, :monitor_this_installation).present?
    creation_attributes.fetch("retention_policy_attributes", {}).each do |key, value|
      values["project[retention_policy_attributes][#{key}]"] = value
    end
    values
  end

  # The step that owns a validation error, so a failed create lands where it can
  # be fixed.
  def creation_step_for_errors(project)
    keys = project.errors.attribute_names.map(&:to_s)
    return "platform" if keys.include?("integration_kind") && project.errors.attribute_names.exclude?(:name)
    return "retention" if project.retention_policy&.errors&.any? || keys.any? { |key| key.start_with?("retention_policy") }
    return "details" if keys.any? { |key| %w[name slug description user].include?(key) }
    return "details" if project.errors[:base].any? { |message| message.match?(/self-monitoring|admin|Ruby/i) }

    "retention"
  end
end
