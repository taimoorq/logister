# frozen_string_literal: true

class ErrorGroupJsonExporter
  include ProjectEvents::PayloadSupport

  RECENT_TREND_DAYS = 14
  OCCURRENCE_RECORD_LIMIT = 50
  RELATED_LOG_LIMIT = 50
  RELATED_LOG_WINDOW = 5.minutes

  def self.call(project:, group:, include_occurrences: false, generated_at: Time.current, logister_url: nil)
    new(
      project: project,
      group: group,
      include_occurrences: include_occurrences,
      generated_at: generated_at,
      logister_url: logister_url
    ).call
  end

  def initialize(project:, group:, include_occurrences:, generated_at:, logister_url:)
    @project = project
    @group = group
    @include_occurrences = include_occurrences
    @generated_at = generated_at
    @logister_url = logister_url
  end

  def call
    {
      "export" => export_payload,
      "project" => project_payload,
      "error_group" => group_payload,
      "assignment" => assignment_payload,
      "latest_event" => event_payload(latest_event),
      "exception" => exception_payload(latest_event),
      "request" => request_payload(latest_event),
      "occurrences" => occurrences_payload,
      "related_logs" => related_logs_payload(latest_event),
      "source_repositories" => source_repositories_payload,
      "deployment_context" => deployment_context_payload(latest_event),
      "external_links" => external_links_payload
    }
  end

  private

  attr_reader :project, :group, :include_occurrences, :generated_at, :logister_url

  def export_payload
    {
      "format" => "logister_error_group",
      "version" => 1,
      "generated_at" => timestamp(generated_at),
      "include_all_occurrences" => false,
      "include_occurrence_records" => include_occurrences,
      "occurrence_record_limit" => include_occurrences ? OCCURRENCE_RECORD_LIMIT : nil,
      "logister_url" => logister_url
    }
  end

  def project_payload
    {
      "uuid" => project.uuid,
      "name" => project.name,
      "slug" => project.slug,
      "integration_kind" => project.integration_kind,
      "integration_label" => project.integration_label,
      "archived_at" => timestamp(project.archived_at),
      "created_at" => timestamp(project.created_at),
      "updated_at" => timestamp(project.updated_at)
    }
  end

  def group_payload
    {
      "uuid" => group.uuid,
      "fingerprint" => group.fingerprint,
      "title" => group.title,
      "subtitle" => group.subtitle,
      "stage" => group.stage,
      "severity" => group.severity,
      "status" => group.status,
      "occurrence_count" => group.occurrence_count,
      "first_seen_at" => timestamp(group.first_seen_at),
      "last_seen_at" => timestamp(group.last_seen_at),
      "resolved_at" => timestamp(group.resolved_at),
      "ignored_at" => timestamp(group.ignored_at),
      "archived_at" => timestamp(group.archived_at),
      "reopen_count" => group.reopen_count,
      "last_reopened_at" => timestamp(group.last_reopened_at),
      "regression_count" => group.regression_count,
      "releases" => {
        "introduced" => group.introduced_in_release,
        "last_seen" => group.last_seen_release,
        "resolved" => group.resolved_in_release,
        "regressed" => group.regressed_in_release
      },
      "created_at" => timestamp(group.created_at),
      "updated_at" => timestamp(group.updated_at)
    }
  end

  def assignment_payload
    {
      "assignee" => user_payload(group.assignee),
      "assigned_by" => user_payload(group.assigned_by),
      "assigned_at" => timestamp(group.assigned_at)
    }
  end

  def latest_event
    @latest_event ||= group.latest_event_record
  end

  def event_payload(event)
    return nil unless event

    {
      "id" => event.id,
      "uuid" => event.uuid,
      "event_type" => event.event_type,
      "level" => event.level,
      "message" => event.message,
      "fingerprint" => event.fingerprint,
      "occurred_at" => timestamp(event.occurred_at),
      "created_at" => timestamp(event.created_at),
      "updated_at" => timestamp(event.updated_at),
      "environment" => IngestEvent.environment(event, nil),
      "release" => IngestEvent.release(event),
      "transaction_name" => IngestEvent.transaction_name(event),
      "trace_id" => IngestEvent.trace_id(event),
      "request_id" => IngestEvent.request_id(event),
      "session_id" => IngestEvent.session_id(event),
      "user_identifier" => IngestEvent.user_identifier(event),
      "api_key" => api_key_payload(event.api_key),
      "context" => json_value(event.context)
    }
  end

  def exception_payload(event)
    return nil unless event

    exception_data = event_exception_data(event)
    backtrace = event_backtrace(exception_data)
    frames = parse_backtrace_frames(backtrace)

    {
      "data" => json_value(exception_data),
      "backtrace" => json_value(backtrace),
      "frames" => frames.map { |frame| frame_payload(frame) },
      "application_frames" => frames.select { |frame| frame[:application_frame] }.map { |frame| frame_payload(frame) },
      "local_variables" => json_value(event_local_variables(exception_data)),
      "instance_variables" => json_value(event_instance_variables(exception_data))
    }
  end

  def request_payload(event)
    return nil unless event

    json_value(ProjectEvents::RequestContextPresenter.new(event).details)
  end

  def occurrences_payload
    return full_occurrences_payload if include_occurrences

    occurrence_summary_payload
  end

  def occurrence_summary_payload
    occurrence_scope = group.error_occurrences

    {
      "mode" => "summary",
      "total_count" => group.occurrence_count,
      "stored_count" => occurrence_scope.count,
      "first_occurrence_at" => timestamp(occurrence_scope.minimum(:occurred_at) || group.first_seen_at),
      "last_occurrence_at" => timestamp(occurrence_scope.maximum(:occurred_at) || group.last_seen_at),
      "daily_counts_last_#{RECENT_TREND_DAYS}_days" => daily_occurrence_counts(occurrence_scope, days: RECENT_TREND_DAYS)
    }
  end

  def full_occurrences_payload
    occurrence_scope = group.error_occurrences
    stored_count = occurrence_scope.count
    occurrences = occurrence_scope.recent_first.limit(OCCURRENCE_RECORD_LIMIT).to_a
    events_by_id = IngestEvent.partition_reference_index(
      occurrences,
      id_key: :ingest_event_id,
      occurred_at_key: :ingest_event_occurred_at,
      includes: :api_key
    )

    {
      "mode" => "latest_records",
      "total_count" => group.occurrence_count,
      "stored_count" => stored_count,
      "record_limit" => OCCURRENCE_RECORD_LIMIT,
      "records_included" => occurrences.size,
      "truncated" => stored_count > occurrences.size,
      "records" => occurrences.map do |occurrence|
        event = events_by_id[occurrence.ingest_event_id]
        occurrence.ingest_event_record = event if event
        occurrence_payload(occurrence, event)
      end
    }
  end

  def occurrence_payload(occurrence, event)
    {
      "uuid" => occurrence.uuid,
      "occurred_at" => timestamp(occurrence.occurred_at),
      "created_at" => timestamp(occurrence.created_at),
      "updated_at" => timestamp(occurrence.updated_at),
      "ingest_event" => event_payload(event)
    }
  end

  def related_logs_payload(event)
    return { "window_seconds" => RELATED_LOG_WINDOW.to_i, "limit" => RELATED_LOG_LIMIT, "count" => 0, "records" => [] } unless event

    logs = IngestEvent.related_logs(project: project, event: event, window: RELATED_LOG_WINDOW, limit: RELATED_LOG_LIMIT)

    {
      "window_seconds" => RELATED_LOG_WINDOW.to_i,
      "limit" => RELATED_LOG_LIMIT,
      "count" => logs.size,
      "records" => logs.map { |log_event| event_payload(log_event) }
    }
  end

  def source_repositories_payload
    project.source_repositories.github
           .includes(:github_installation, :github_repository)
           .order(:full_name)
           .map do |repository|
      {
        "uuid" => repository.uuid,
        "provider" => repository.provider,
        "full_name" => repository.full_name,
        "owner_name" => repository.owner_name,
        "repo_name" => repository.repo_name,
        "enabled" => repository.enabled?,
        "configured" => repository.configured?,
        "default_branch" => repository.default_branch,
        "runtime_root" => repository.runtime_root,
        "source_root" => repository.source_root,
        "external_id" => repository.external_id,
        "last_synced_at" => timestamp(repository.last_synced_at),
        "metadata" => json_value(repository.metadata),
        "github_installation" => github_installation_payload(repository.effective_github_installation),
        "github_repository" => github_repository_payload(repository.github_repository)
      }
    end
  end

  def deployment_context_payload(event)
    context = ProjectDeploymentContext.call(project: project, group: group, event: event)

    {
      "matched" => deployment_payload(context.deployment),
      "previous" => deployment_payload(context.previous_deployment),
      "started_after_deployment" => context.started_after,
      "minutes_after_deployment" => context.minutes_after,
      "exact_release" => context.exact_release?
    }
  end

  def external_links_payload
    group.external_links.recent_first.includes(:created_by).map do |link|
      {
        "uuid" => link.uuid,
        "provider" => link.provider,
        "link_type" => link.link_type,
        "url" => link.url,
        "title" => link.title,
        "display_label" => link.display_label,
        "repository_full_name" => link.repository_full_name,
        "external_id" => link.external_id,
        "metadata" => json_value(link.metadata),
        "created_by" => user_payload(link.created_by),
        "created_at" => timestamp(link.created_at),
        "updated_at" => timestamp(link.updated_at)
      }
    end
  end

  def deployment_payload(deployment)
    return nil unless deployment

    {
      "uuid" => deployment.uuid,
      "provider" => deployment.provider,
      "repository_full_name" => deployment.repository_full_name,
      "environment" => deployment.environment,
      "release" => deployment.release,
      "commit_sha" => deployment.commit_sha,
      "short_commit_sha" => deployment.short_commit_sha,
      "branch" => deployment.branch,
      "deployed_at" => timestamp(deployment.deployed_at),
      "source" => deployment.source,
      "github_commit_url" => deployment.github_commit_url,
      "pull_request_number" => deployment.pull_request_number,
      "pull_request_url" => deployment.pull_request_url,
      "release_url" => deployment.release_url,
      "metadata" => json_value(deployment.metadata),
      "created_at" => timestamp(deployment.created_at),
      "updated_at" => timestamp(deployment.updated_at)
    }
  end

  def github_installation_payload(installation)
    return nil unless installation

    {
      "uuid" => installation.uuid,
      "installation_id" => installation.installation_id,
      "account_login" => installation.account_login,
      "account_type" => installation.account_type,
      "repository_selection" => installation.repository_selection,
      "active" => installation.active?,
      "suspended_at" => timestamp(installation.suspended_at),
      "permissions" => json_value(installation.permissions),
      "events" => json_value(installation.events),
      "created_at" => timestamp(installation.created_at),
      "updated_at" => timestamp(installation.updated_at)
    }
  end

  def github_repository_payload(repository)
    return nil unless repository

    {
      "external_id" => repository.external_id,
      "full_name" => repository.full_name,
      "owner_name" => repository.owner_name,
      "repo_name" => repository.repo_name,
      "default_branch" => repository.default_branch,
      "html_url" => repository.html_url,
      "private" => repository.private?,
      "archived" => repository.archived?,
      "active" => repository.active?,
      "permissions" => json_value(repository.permissions),
      "metadata" => json_value(repository.metadata),
      "last_synced_at" => timestamp(repository.last_synced_at)
    }
  end

  def api_key_payload(api_key)
    return nil unless api_key

    {
      "uuid" => api_key.uuid,
      "name" => api_key.name,
      "active" => api_key.active?,
      "last_used_at" => timestamp(api_key.last_used_at),
      "created_at" => timestamp(api_key.created_at),
      "updated_at" => timestamp(api_key.updated_at)
    }
  end

  def user_payload(user)
    return nil unless user

    {
      "uuid" => user.uuid,
      "email" => user.email,
      "name" => user.name
    }
  end

  def frame_payload(frame)
    {
      "raw" => frame[:raw],
      "file" => frame[:file],
      "line_number" => frame[:line_number],
      "column_number" => frame[:column_number],
      "method_name" => frame[:method_name],
      "code_context" => frame[:code_context],
      "locals" => json_value(frame[:locals]),
      "application_frame" => frame[:application_frame]
    }
  end

  def daily_occurrence_counts(scope, days:)
    reference_date = (group.last_seen_at || Time.current).to_date
    start_date = reference_date - (days - 1)
    counts = scope
             .where("occurred_at >= ?", start_date.beginning_of_day)
             .group("DATE(occurred_at)")
             .count
             .transform_keys { |date| date.to_date }

    (start_date..reference_date).map do |date|
      {
        "date" => date.iso8601,
        "count" => counts.fetch(date, 0)
      }
    end
  end

  def event_exception_data(event)
    context = event_context_hash(event)
    normalize_hash(context["exception"] || context[:exception])
  end

  def event_backtrace(exception_data)
    exception_hash = normalize_hash(exception_data)
    exception_hash["backtrace"] || exception_hash[:backtrace]
  end

  def event_local_variables(exception_data)
    exception_hash = normalize_hash(exception_data)
    normalize_hash(
      exception_hash["locals"] ||
      exception_hash[:locals] ||
      exception_hash["local_variables"] ||
      exception_hash[:local_variables]
    )
  end

  def event_instance_variables(exception_data)
    exception_hash = normalize_hash(exception_data)
    normalize_hash(exception_hash["instance_variables"] || exception_hash[:instance_variables])
  end

  def timestamp(value)
    value&.utc&.iso8601(6)
  end

  def json_value(value)
    value.as_json
  end
end
