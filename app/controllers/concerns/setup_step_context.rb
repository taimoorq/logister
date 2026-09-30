# frozen_string_literal: true

# Builds everything a setup wizard step needs to render. Shared by the wizard
# controller and by the controllers behind its embedded forms, so a failed
# submission can re-render the same step with the submitted values.
module SetupStepContext
  extend ActiveSupport::Concern
  include ProjectSettingsContext

  # Which settings data each embedded step's form needs.
  CONTEXT_FOR_STEP = {
    api_key: :setup,
    teammates: :team,
    alerts: :notifications,
    source_repo: :integrations,
    mapping: :integrations,
    symbols: :integrations,
    google_play: :integrations,
    app_store: :integrations
  }.freeze

  # Steps whose evidence is worth showing as the actual thing that arrived.
  RECEIPT_STEPS = %i[first_event first_diagnostic].freeze

  private

  # `only` narrows the plan to that step and what it waits on, for the cheap
  # repeated live check; the full plan is only needed to say where Continue goes.
  def prepare_setup_step(group_key, step_key, only: nil)
    @plan = only ? ProjectSetupPlan.for_steps(@project, [ only ], viewer: current_user) : ProjectSetupPlan.for(@project, viewer: current_user)
    @group = @plan.group_view(group_key) || raise(ActiveRecord::RecordNotFound)
    @item = @group.items.find { |candidate| candidate.key.to_s == step_key.to_s } || raise(ActiveRecord::RecordNotFound)
    @setup_return = "#{@group.key}/#{@item.key}"
    @wizard_frame = WizardFrame.new(
      context: @project.name,
      detail: "Setup: #{@group.label}",
      exit_label: "Save and exit",
      exit_path: setup_project_path(@project),
      progress_label: "#{@group.label} progress",
      done: @group.done_count,
      total: @group.total
    )
  end

  # The rest of what the step page shows, for the full page (not the live check).
  def load_setup_step_page
    @receipt = latest_setup_receipt if RECEIPT_STEPS.include?(@item.key)
    @next_item = @plan.continue_item_after(@item)
    @previous_item = @plan.previous_item_before(@item)
    @step_index = @group.items.index(@item)
    @wizard_kind = @item.presentation
    @self_monitoring_status = Logister::SelfMonitoringStatus.new(project: @project) if @wizard_kind == :guide
    context = CONTEXT_FOR_STEP[@item.key]
    return unless context && @wizard_kind == :embedded

    @settings_section = context.to_s
    load_project_settings_context(include: context)
  end

  def latest_setup_receipt
    event = @project.ingest_events.order(created_at: :desc).select(:id, :event_type, :message, :context, :created_at).first
    return unless event

    context = event.context.is_a?(Hash) ? event.context : {}
    {
      event_type: event.event_type,
      message: event.message.to_s.truncate(140),
      environment: context["environment"].presence,
      release: context["release"].presence,
      received_at: event.created_at
    }
  end
end
