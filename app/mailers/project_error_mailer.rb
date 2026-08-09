class ProjectErrorMailer < ApplicationMailer
  def first_occurrence(delivery)
    @delivery = delivery
    @user = delivery.user
    @project = delivery.project
    @group = delivery.error_group
    @metadata = delivery.metadata.to_h
    @event = ProjectNotificationEvidence.event_for(error_group: @group, metadata: @metadata) || @group.latest_event_record
    @evidence = TelemetryEvidence.for(@event)
    @imprecise_source_time = @evidence.reporting_interval? || @evidence.received_only?
    @preference = ProjectNotificationPreference.for(user: @user, project: @project)
    @group_url = project_url(@project, group_uuid: @group.uuid)
    @settings_url = settings_project_url(@project, anchor: "notifications")

    apply_notification_headers(kind: "first_occurrence", preference: @preference, project: @project)

    mail(
      to: @user.email,
      subject: "[Logister] #{@imprecise_source_time ? 'Newly received diagnostic' : 'New error'} in #{@project.name}: #{@group.title.to_s.truncate(80)}"
    )
  end

  def digest(delivery)
    @delivery = delivery
    @user = delivery.user
    @project = delivery.project
    @preference = ProjectNotificationPreference.for(user: @user, project: @project)
    @period_start = delivery.period_start_at
    @period_end = delivery.period_end_at
    @frequency = delivery.metadata["digest_frequency"].presence || delivery.notification_kind.delete_suffix("_digest")
    @summary = ErrorDigestSummary.new(project: @project, period_start: @period_start, period_end: @period_end)
    @project_url = project_url(@project)
    @settings_url = settings_project_url(@project, anchor: "notifications")

    apply_notification_headers(kind: "#{@frequency}_digest", preference: @preference, project: @project)

    mail(
      to: @user.email,
      subject: "[Logister] #{@frequency.titleize} error digest for #{@project.name}: #{@summary.total_occurrences} occurrences"
    )
  end

  def group_alert(delivery)
    @delivery = delivery
    @user = delivery.user
    @project = delivery.project
    @group = delivery.error_group
    @preference = ProjectNotificationPreference.for(user: @user, project: @project)
    @notification_label = notification_kind_label(delivery.notification_kind)
    @metadata = delivery.metadata || {}
    @group_url = inbox_project_url(@project, group_uuid: @group.uuid)
    @settings_url = settings_project_url(@project, anchor: "notifications")

    apply_notification_headers(kind: delivery.notification_kind, preference: @preference, project: @project)

    mail(
      to: @user.email,
      subject: "[Logister] #{@notification_label} in #{@project.name}: #{@group.title.to_s.truncate(80)}"
    )
  end

  def monitor_alert(delivery)
    @delivery = delivery
    @user = delivery.user
    @project = delivery.project
    @preference = ProjectNotificationPreference.for(user: @user, project: @project)
    @metadata = delivery.metadata || {}
    @monitor = @project.check_in_monitors.find_by(id: @metadata["monitor_id"])
    @notification_label = notification_kind_label(delivery.notification_kind)
    @monitor_url = monitors_project_url(@project)
    @settings_url = settings_project_url(@project, anchor: "notifications")

    apply_notification_headers(kind: delivery.notification_kind, preference: @preference, project: @project)

    mail(
      to: @user.email,
      subject: "[Logister] #{@notification_label} for #{@project.name}: #{@metadata["monitor_slug"].presence || @monitor&.slug || "monitor"}"
    )
  end

  def project_alert(delivery)
    @delivery = delivery
    @user = delivery.user
    @project = delivery.project
    @preference = ProjectNotificationPreference.for(user: @user, project: @project)
    @metadata = delivery.metadata || {}
    @notification_label = notification_kind_label(delivery.notification_kind)
    @project_url = project_url(@project)
    @settings_url = settings_project_url(@project, anchor: "notifications")

    apply_notification_headers(kind: delivery.notification_kind, preference: @preference, project: @project)

    mail(
      to: @user.email,
      subject: "[Logister] #{@notification_label} for #{@project.name}"
    )
  end

  private

  def apply_notification_headers(kind:, preference:, project:)
    unsubscribe_url = unsubscribe_notification_preferences_url(token: preference.unsubscribe_token)

    headers["List-Unsubscribe"] = "<#{unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    configuration_set = InstanceConfiguration.value("email.configuration_set")
    headers["X-SES-CONFIGURATION-SET"] = configuration_set if configuration_set.present?
    headers["X-SES-MESSAGE-TAGS"] = "kind=#{tag_value(kind)}, project=project_#{project.id}"
  end

  def tag_value(value)
    value.to_s.gsub(/[^A-Za-z0-9_-]/, "_").presence || "notification"
  end

  def notification_kind_label(kind)
    {
      "regression" => "Reopened error",
      "frequent_error" => "Frequent error",
      "error_milestone" => "Error milestone",
      "assignment" => "Error assignment",
      "status_change" => "Error status change",
      "monitor_missed" => "Monitor missed",
      "monitor_recovered" => "Monitor recovered",
      "project_spike" => "Project error spike",
      "performance_threshold" => "Performance threshold",
      "release_summary" => "Release summary",
      "usage_alert" => "Usage alert",
      "retention_failure" => "Retention archive failure",
      "mobile_artifact_health" => "Mobile artifact coverage needs attention",
      "mobile_source_health" => "Mobile reporting source needs attention",
      "mobile_intake_health" => "Mobile intake needs attention"
    }.fetch(kind.to_s, kind.to_s.humanize)
  end
end
