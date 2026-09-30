# frozen_string_literal: true

class ProjectSetupStatus
  attr_reader :project

  def initialize(project)
    @project = project
  end

  # Evidence for the catalog's steps for this project's type. Pass `keys` to
  # load only the evidence a caller needs (for example, skipping archive
  # evidence when archive exports are off).
  def call(keys: nil)
    mobile = project.integration_android? || project.integration_ios?
    context = mobile ? latest_context : {}
    sdk = context.fetch("sdk", {})
    capabilities = ProjectCapabilitySnapshot.for(project)

    loaders = {
      active_api_key: -> { existence_status(:active_api_key, project.api_keys.active.maximum(:created_at), "No active API key is available.", :create_api_key) },
      has_events: -> { existence_status(:has_events, latest_event&.created_at, "No telemetry receipt has been accepted yet.", :send_first_event) },
      source_repository: -> { existence_status(:source_repository, project.source_repositories.enabled.maximum(:created_at), "No enabled source repository is connected.", :connect_source_repository) },
      deployments: -> { existence_status(:deployments, project.deployments.maximum(:created_at), "No deployment evidence has been recorded.", :record_deployment) },
      mobile_token: -> { existence_status(:mobile_token, active_mobile_token_at, "No unexpired mobile ingest token is available.", :issue_mobile_token) },
      release_metadata: -> { existence_status(:release_metadata, dimension_observed_at("app_version", require_also: "build_number"), "No diagnostic has supplied both app version and build number.", :capture_release_metadata) },
      app_build_metadata: -> { existence_status(:app_build_metadata, dimension_observed_at("app_identifier", require_also: %w[app_version build_number]), "No diagnostic has supplied bundle identifier, version, and build number together.", :capture_release_metadata) },
      sessions: -> { existence_status(:sessions, occurrence_scope.where.not(session_hash: nil).maximum(:created_at), "No scoped session correlation evidence has been observed.", :configure_sessions) },
      installations: -> { existence_status(:installations, occurrence_scope.where.not(installation_hash: nil).maximum(:created_at), "No scoped installation pseudonym has been observed.", :configure_installations) },
      breadcrumbs: -> { boolean_status(:breadcrumbs, Array(context["breadcrumbs"]).any?, latest_event&.created_at, "The latest received event has no bounded breadcrumb trail.", :configure_breadcrumbs) },
      automatic_capture: -> { boolean_status(:automatic_capture, sdk["automatic_crash_capture"] == true, latest_event&.created_at, "Automatic crash capture has not been verified in the latest client evidence.", :configure_automatic_capture) },
      metric_kit: -> { existence_status(:metric_kit, dimension_observed_at("diagnostic_source", equals: "metrickit"), "No MetricKit diagnostic receipt has been observed.", :configure_metric_kit) },
      performance: -> { existence_status(:performance, performance_observed_at, "No transaction or span was received in the last #{PERFORMANCE_WINDOW.inspect}.", :send_performance) },
      teammates: -> { teammate_status },
      project_links: -> { existence_status(:project_links, ProjectLink.touching(project).maximum(:created_at), "No related project is linked yet.", :link_projects, verified_reason: "This project is linked to another Logister project.") },
      check_ins: -> { capabilities.status(:check_ins) },
      archive_exports: -> { existence_status(:archive_exports, project.telemetry_archives.completed.maximum(:created_at), "Archive exports are on, and no archive has completed yet.", :review_archive_exports, verified_reason: "At least one telemetry archive has completed.") },
      android_mapping: -> { capabilities.status(:stack_mapping) },
      google_play: -> { capabilities.status(:distribution_store) },
      apple_symbols: -> { capabilities.status(:symbol_artifacts) },
      app_store: -> { capabilities.status(:distribution_store) }
    }
    keys ||= ProjectSetupCatalog.evidence_keys_for(project.integration_definition.default_experience_key) - [ :alerts ]
    loaders.slice(*keys).transform_values(&:call).freeze
  end

  private

  PERFORMANCE_WINDOW = 30.days

  def latest_event
    @latest_event ||= project.ingest_events.order(created_at: :desc).select(:id, :context, :created_at).first
  end

  def latest_context
    MobileTelemetryNormalizer.normalize(latest_event&.context)
  end

  def occurrence_scope
    @occurrence_scope ||= ErrorOccurrence.joins(:error_group).where(error_groups: { project_id: project.id })
  end

  def active_mobile_token_at
    project.mobile_ingest_tokens.where(revoked_at: nil).where("expires_at > ?", Time.current).maximum(:created_at)
  end

  def dimension_observed_at(key, equals: nil, require_also: nil)
    scope = occurrence_scope.where("COALESCE(error_occurrences.dimensions ->> ?, '') <> ''", key)
    scope = scope.where_json_text(:dimensions, paths: [ [ key ] ], value: equals) if equals
    Array(require_also).each do |required_key|
      scope = scope.where("COALESCE(error_occurrences.dimensions ->> ?, '') <> ''", required_key)
    end
    scope.maximum(:created_at)
  end

  # Uses the (project_id, occurred_at DESC) partial index for transactions and the
  # (project_id, started_at DESC) span index, so "nothing yet" stays a single
  # index probe instead of a scan of the whole window.
  def performance_observed_at
    since = PERFORMANCE_WINDOW.ago
    transaction_at = project.ingest_events.transactions.where("occurred_at >= ?", since).order(occurred_at: :desc).limit(1).pick(:occurred_at)
    span_at = project.trace_spans.where("started_at >= ?", since).order(started_at: :desc).limit(1).pick(:started_at)
    [ transaction_at, span_at ].compact.max
  end

  def teammate_status
    count = project.project_memberships.count
    status(
      :teammates,
      count.positive? ? :configured : :unconfigured,
      observed_at: project.project_memberships.maximum(:created_at),
      evidence_count: count,
      reason: count.positive? ? "#{count} #{'teammate'.pluralize(count)} can open this project." : "Only the project owner has access.",
      action_key: :invite_teammate
    )
  end

  def existence_status(key, observed_at, missing_reason, action_key, verified_reason: nil)
    status(
      key,
      observed_at ? :configured : :unconfigured,
      observed_at:,
      reason: observed_at ? (verified_reason || "Verified from project evidence received #{time_description(observed_at)}.") : missing_reason,
      action_key:
    )
  end

  def boolean_status(key, configured, observed_at, missing_reason, action_key)
    status(
      key,
      configured ? :configured : (observed_at ? :partial : :unconfigured),
      observed_at:,
      reason: configured ? "Verified in the latest received client evidence." : missing_reason,
      action_key:
    )
  end

  def status(key, state, observed_at: nil, reason: nil, action_key: nil, evidence_count: nil)
    CapabilityStatus.new(
      key:,
      state:,
      provenance: :setup_evidence,
      observed_at:,
      evidence_count:,
      reason:,
      action_key:
    )
  end

  def time_description(time)
    ActionController::Base.helpers.time_ago_in_words(time) + " ago"
  end
end
