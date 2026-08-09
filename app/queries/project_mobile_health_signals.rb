# frozen_string_literal: true

class ProjectMobileHealthSignals
  Signal = Data.define(:kind, :subject_key, :state, :metadata)

  INTAKE_STALE_AFTER = 2.days
  INTAKE_BASELINE_WINDOW = 14.days
  INTAKE_MIN_EVENTS = 20
  INTAKE_MIN_ACTIVE_DAYS = 3
  ARTIFACT_ALERT_STATES = %i[unconfigured partial blocked failed].freeze
  SOURCE_ALERT_STATES = %i[stale failed].freeze

  attr_reader :project, :now, :capability_snapshot

  def initialize(project, now: Time.current, capability_snapshot: nil)
    raise ArgumentError, "Mobile health signals are available only for Android and iOS projects" unless project.integration_android? || project.integration_ios?

    @project = project
    @now = now
    @capability_snapshot = capability_snapshot || ProjectCapabilitySnapshot.for(project)
  end

  def call
    [ artifact_signal, source_signal, intake_signal ].compact.freeze
  end

  private

  def artifact_signal
    key = project.integration_android? ? :stack_mapping : :symbol_artifacts
    status = capability_snapshot.status(key)
    return unless ARTIFACT_ALERT_STATES.include?(status.state)
    return unless status.evidence_count.to_i.positive?

    signal(
      kind: "mobile_artifact_health",
      subject_key: key,
      status: status,
      summary: project.integration_android? ? "Observed builds need R8 mapping coverage." : "Observed binaries need dSYM coverage.",
      recovery_action: project.integration_android? ? "Upload the exact mapping.txt for each affected package and version code from Artifacts." : "Upload a zipped dSYM for every missing binary UUID and architecture from Artifacts."
    )
  end

  def source_signal
    status = capability_snapshot.status(:distribution_store)
    return unless SOURCE_ALERT_STATES.include?(status.state)

    signal(
      kind: "mobile_source_health",
      subject_key: :distribution_store,
      status: status,
      summary: project.integration_android? ? "Google Play reporting needs attention." : "App Store Connect reporting needs attention.",
      recovery_action: "Review the bounded provider error and credentials in Integrations, then run a successful import."
    )
  end

  def intake_signal
    latest_receipt_at = project.ingest_events.maximum(:created_at)
    return unless latest_receipt_at && latest_receipt_at < now - INTAKE_STALE_AFTER

    baseline_end = now - INTAKE_STALE_AFTER
    baseline = project.ingest_events.where(created_at: (now - INTAKE_BASELINE_WINDOW)..baseline_end)
    baseline_event_count = baseline.count
    return if baseline_event_count < INTAKE_MIN_EVENTS

    active_days = baseline.group(Arel.sql("DATE(ingest_events.created_at)")).count.size
    return if active_days < INTAKE_MIN_ACTIVE_DAYS

    Signal.new(
      kind: "mobile_intake_health",
      subject_key: "receipt_stale",
      state: :stale,
      metadata: {
        "signal" => "Mobile intake receipt gap",
        "state" => "stale",
        "summary" => "A previously active mobile project has not delivered telemetry recently.",
        "reason" => "No event has been received for at least #{INTAKE_STALE_AFTER.inspect} after #{baseline_event_count} receipts across #{active_days} active days in the baseline window.",
        "latest_receipt_at" => latest_receipt_at.utc.iso8601,
        "baseline_event_count" => baseline_event_count,
        "baseline_active_days" => active_days,
        "detected_at" => now.utc.iso8601,
        "recovery_action" => "Verify the current app release, collection consent, token issuer, durable queue health, and successful flush. This signal does not prove client queue loss."
      }.freeze
    ).freeze
  end

  def signal(kind:, subject_key:, status:, summary:, recovery_action:)
    Signal.new(
      kind: kind,
      subject_key: "#{subject_key}:#{status.state}",
      state: status.state,
      metadata: {
        "signal" => kind.humanize,
        "state" => status.state.to_s,
        "summary" => summary,
        "reason" => status.reason,
        "observed_at" => status.observed_at&.utc&.iso8601,
        "evidence_count" => status.evidence_count,
        "detected_at" => now.utc.iso8601,
        "recovery_action" => recovery_action
      }.compact.freeze
    ).freeze
  end
end
