# frozen_string_literal: true

class ProjectNotificationPreferenceRules
  def self.immediate_email_enabled?(preference, kind, error_group:, metadata:)
    new(preference).immediate_email_enabled?(kind, error_group: error_group, metadata: metadata)
  end

  def initialize(preference)
    @preference = preference
  end

  def immediate_email_enabled?(kind, error_group:, metadata:)
    case kind.to_s
    when "first_occurrence"
      preference.first_occurrence_enabled? && error_group_matches_filters?(error_group)
    when "regression"
      preference.regression_enabled? && error_group_matches_filters?(error_group)
    when "frequent_error"
      preference.frequent_error_enabled? && error_group_matches_filters?(error_group)
    when "error_milestone"
      preference.milestone_alerts_enabled? && error_group_matches_filters?(error_group)
    when "assignment", "status_change"
      workflow_email_enabled?(kind, error_group: error_group, metadata: metadata)
    when "monitor_missed", "monitor_recovered"
      preference.monitor_alerts_enabled?
    when "project_spike"
      preference.project_spike_enabled?
    when "performance_threshold"
      preference.performance_alerts_enabled?
    when "release_summary"
      preference.release_notifications_enabled?
    when "usage_alert"
      preference.usage_notifications_enabled?
    when "retention_failure"
      preference.retention_notifications_enabled?
    else
      false
    end
  end

  private

  attr_reader :preference

  def error_group_matches_filters?(group)
    return true unless group

    return false unless environment_matches?(group.stage)
    return false unless severity_matches?(group.severity)

    status_matches?(group.status)
  end

  def workflow_email_enabled?(kind, error_group:, metadata:)
    return false if preference.workflow_mode == "off"
    return false unless error_group_matches_filters?(error_group)
    return true if preference.workflow_mode == "all_project"

    case kind.to_s
    when "assignment"
      metadata_user_id(metadata, "assigned_user_id") == preference.user_id
    when "status_change"
      error_group&.assigned_user_id == preference.user_id &&
        metadata_user_id(metadata, "actor_user_id") != preference.user_id
    else
      false
    end
  end

  def environment_matches?(environment)
    preference.environment_filter == ProjectNotificationPreference::FILTER_ALL ||
      preference.environment_filter == environment.to_s
  end

  def severity_matches?(severity)
    preference.severity_filter == ProjectNotificationPreference::FILTER_ALL ||
      preference.severity_filter == severity.to_s
  end

  def status_matches?(status)
    case preference.status_filter
    when "all"
      true
    when "closed"
      status.to_s != "unresolved"
    else
      status.to_s == preference.status_filter
    end
  end

  def metadata_user_id(metadata, key)
    Integer(metadata[key] || metadata[key.to_sym], exception: false)
  end
end
