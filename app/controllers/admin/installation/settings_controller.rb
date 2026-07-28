# frozen_string_literal: true

class Admin::Installation::SettingsController < Admin::BaseController
  include Admin::Installation::SettingsSupport

  before_action :set_section
  before_action :set_installation

  def show
    prepare_view
  end

  def update
    return test if params[:operation] == "test"

    values = setting_values
    overrides = InstanceConfiguration.candidate_overrides(@section.key, values)
    candidate_fingerprint = InstanceConfiguration.fingerprint(@section.key, overrides: overrides)

    if requesting_clickhouse_reads?(values) && !verified_for_clickhouse_reads?(candidate_fingerprint)
      prepare_view(form_values: values)
      flash.now[:alert] = "Test an enabled ClickHouse configuration with complete coverage before switching reads to ClickHouse. An environment override that keeps ClickHouse disabled must be removed first."
      render :show, status: :unprocessable_content
      return
    end

    keep_verification = verified_for?(candidate_fingerprint)
    InstanceConfiguration.save_section!(
      @section.key,
      values: values,
      clear_keys: params[:clear_keys],
      actor: current_user,
      request_id: request.request_id
    )
    InstanceConfiguration::Runtime.apply!

    current_fingerprint = InstanceConfiguration.fingerprint(@section.key)
    @step.mark_configured!(fingerprint: current_fingerprint) unless keep_verification && candidate_fingerprint == current_fingerprint

    restart = @definitions.any?(&:restart_required?)
    notice = "#{@section.label} settings saved."
    notice += " Restart web and worker processes to apply boot-time changes." if restart
    redirect_to admin_installation_section_path(@section.slug), notice: notice
  rescue ActiveRecord::StaleObjectError
    redirect_to admin_installation_section_path(@section.slug), alert: "These settings changed in another session. Review the current values and try again."
  end

  def test
    values = setting_values
    overrides = InstanceConfiguration.candidate_overrides(@section.key, values)
    effective_values = InstanceConfiguration.values_for(@section.key, overrides: overrides)
    fingerprint = InstanceConfiguration.fingerprint(@section.key, overrides: overrides)
    @diagnostic = if unsaved_email_delivery_test?(fingerprint)
      InstanceConfiguration::Diagnostics::Result.new(
        success: false,
        summary: "Save these SMTP settings before sending direct and queued test messages.",
        details: { "saved_configuration_required" => true }
      )
    else
      InstanceConfiguration::Diagnostics.call(
        @section.key,
        values: effective_values,
        test_recipient: params[:test_recipient]
      )
    end

    if @diagnostic.success?
      @step.mark_verified!(fingerprint: fingerprint, user: current_user, details: @diagnostic.details)
    elsif !@step.verified?
      @step.mark_configured!(fingerprint: fingerprint)
    end

    InstanceConfiguration.audit!(
      key: "section.#{@section.key}",
      action: @diagnostic.success? ? "test_passed" : "test_failed",
      actor: current_user,
      request_id: request.request_id,
      details: { "section" => @section.key, "summary" => @diagnostic.summary }
    )

    prepare_view(form_values: values)
    render :show, status: @diagnostic.success? ? :ok : :unprocessable_content
  end

  def skip
    if @section.required?
      redirect_to admin_installation_section_path(@section.slug), alert: "This section is required and cannot be skipped."
      return
    end

    @step.mark_skipped!(user: current_user)
    InstanceConfiguration.audit!(
      key: "section.#{@section.key}",
      action: "skipped",
      actor: current_user,
      request_id: request.request_id,
      details: { "section" => @section.key }
    )
    redirect_to admin_installation_path, notice: "#{@section.label} marked as skipped. Its saved settings remain available."
  end

  def repair
    return head :not_found unless @section.key == "clickhouse"

    result = Logister::ClickhouseSchemaRepairer.call
    InstanceConfiguration.audit!(
      key: "section.clickhouse",
      action: "schema_repaired",
      actor: current_user,
      request_id: request.request_id,
      details: {
        "section" => "clickhouse",
        "loaded_statements" => result.fetch(:loaded_statements),
        "repaired_columns" => result.fetch(:repaired_columns),
        "rebuilt_views" => result.fetch(:rebuilt_views)
      }
    )
    redirect_to admin_installation_section_path("clickhouse"), notice: "ClickHouse schema repair completed. Run the candidate check before changing the read mode."
  rescue StandardError => error
    Rails.logger.warn("admin ClickHouse schema repair failed: #{error.class}")
    InstanceConfiguration.audit!(
      key: "section.clickhouse",
      action: "schema_repair_failed",
      actor: current_user,
      request_id: request.request_id,
      details: { "section" => "clickhouse", "error_class" => error.class.name }
    )
    redirect_to admin_installation_section_path("clickhouse"), alert: "ClickHouse schema repair failed. Check the app logs, connection, and DDL permissions."
  end
end
