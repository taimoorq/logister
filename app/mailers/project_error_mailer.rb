class ProjectErrorMailer < ApplicationMailer
  def first_occurrence(delivery)
    @delivery = delivery
    @user = delivery.user
    @project = delivery.project
    @group = delivery.error_group
    @event = @group.latest_event
    @preference = ProjectNotificationPreference.for(user: @user, project: @project)
    @group_url = project_url(@project, group_uuid: @group.uuid)
    @settings_url = settings_project_url(@project, anchor: "notifications")

    apply_notification_headers(kind: "first_occurrence", preference: @preference, project: @project)

    mail(
      to: @user.email,
      subject: "[Logister] New error in #{@project.name}: #{@group.title.to_s.truncate(80)}"
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

  private

  def apply_notification_headers(kind:, preference:, project:)
    unsubscribe_url = unsubscribe_notification_preferences_url(token: preference.unsubscribe_token)

    headers["List-Unsubscribe"] = "<#{unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    headers["X-SES-CONFIGURATION-SET"] = ENV["SES_CONFIGURATION_SET"] if ENV["SES_CONFIGURATION_SET"].present?
    headers["X-SES-MESSAGE-TAGS"] = "kind=#{tag_value(kind)}, project=project_#{project.id}"
  end

  def tag_value(value)
    value.to_s.gsub(/[^A-Za-z0-9_-]/, "_").presence || "notification"
  end
end
