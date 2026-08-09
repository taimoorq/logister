# frozen_string_literal: true

class TelemetryEvidenceNormalizer
  CONTRACT_VERSION = 1
  TIME_PRECISIONS = %w[exact reporting_interval received_only].freeze
  Result = Data.define(:context, :canonical_occurred_at, :evidence)

  class << self
    def normalize(context:, client_occurred_at:, received_at:)
      new(
        context: context,
        client_occurred_at: client_occurred_at,
        received_at: received_at
      ).normalize
    end
  end

  def initialize(context:, client_occurred_at:, received_at:)
    @context = context.is_a?(Hash) ? context.deep_dup.stringify_keys : {}
    @client_occurred_at = client_occurred_at
    @received_at = parse_time(received_at) || Time.current
  end

  def normalize
    context.delete("telemetry_evidence")

    exact_occurred_at = parse_time(client_occurred_at) || parse_time(diagnostic["occurred_at"]) || parse_time(submitted_evidence["occurred_at"])
    reporting_start = reporting_time(:start)
    reporting_end = reporting_time(:end)
    reporting_start, reporting_end = nil, nil if reporting_start && reporting_end && reporting_start > reporting_end

    precision = if exact_occurred_at
      "exact"
    elsif reporting_start || reporting_end
      "reporting_interval"
    else
      "received_only"
    end
    canonical_occurred_at = exact_occurred_at || reporting_end || reporting_start || received_at
    evidence = build_evidence(
      precision: precision,
      exact_occurred_at: exact_occurred_at,
      reporting_start: reporting_start,
      reporting_end: reporting_end
    )
    context["telemetry_evidence"] = evidence

    Result.new(context: context, canonical_occurred_at: canonical_occurred_at, evidence: evidence)
  end

  private

  attr_reader :context, :client_occurred_at, :received_at

  def build_evidence(precision:, exact_occurred_at:, reporting_start:, reporting_end:)
    source = normalized_token(
      submitted_evidence["source"] ||
      diagnostic["source"] ||
      error_context["capture_source"] ||
      default_source
    ) || "unknown"
    kind = normalized_token(submitted_evidence["kind"] || diagnostic["kind"] || error_context["mechanism"])
    capture_mode = normalized_token(
      submitted_evidence["capture_mode"] ||
      diagnostic["capture_mode"] ||
      error_context["capture_source"] ||
      source
    )

    {
      "schema_version" => CONTRACT_VERSION,
      "source" => source,
      "kind" => kind,
      "capture_mode" => capture_mode,
      "evidence_kind" => normalized_token(submitted_evidence["evidence_kind"]) || evidence_kind_for(kind, source),
      "identity_scope" => normalized_token(submitted_evidence["identity_scope"]) || identity_scope_for(source),
      "fatality" => fatality,
      "time" => {
        "precision" => precision,
        "occurred_at" => iso8601(exact_occurred_at),
        "reporting_start" => iso8601(reporting_start),
        "reporting_end" => iso8601(reporting_end),
        "received_at" => iso8601(received_at)
      }.compact,
      "producer" => producer,
      "normalization" => {
        "owner" => "server",
        "normalizer" => self.class.name,
        "sensitive_key_filter_applied" => true
      }
    }.compact
  end

  def submitted_evidence
    @submitted_evidence ||= begin
      value = context["evidence"]
      value.is_a?(Hash) ? value.stringify_keys : {}
    end
  end

  def diagnostic
    @diagnostic ||= context["diagnostic"].is_a?(Hash) ? context["diagnostic"].stringify_keys : {}
  end

  def error_context
    @error_context ||= context["error"].is_a?(Hash) ? context["error"].stringify_keys : {}
  end

  def producer
    sdk = context["sdk"].is_a?(Hash) ? context["sdk"].stringify_keys : {}
    values = {
      "sdk_name" => normalized_scalar(submitted_producer["sdk_name"] || sdk["name"]),
      "sdk_version" => normalized_scalar(submitted_producer["sdk_version"] || sdk["version"]),
      "telemetry_schema_version" => positive_integer(context["telemetry_schema_version"]),
      "decoder_version" => normalized_scalar(submitted_producer["decoder_version"])
    }.compact
    values.presence
  end

  def submitted_producer
    @submitted_producer ||= begin
      value = submitted_evidence["producer"]
      value.is_a?(Hash) ? value.stringify_keys : {}
    end
  end

  def reporting_time(boundary)
    period = submitted_evidence["reporting_period"].is_a?(Hash) ? submitted_evidence["reporting_period"].stringify_keys : {}
    diagnostic_period = diagnostic["reporting_period"].is_a?(Hash) ? diagnostic["reporting_period"].stringify_keys : {}
    candidates = if boundary == :start
      [
        period["start"],
        submitted_evidence["reporting_start"],
        diagnostic_period["start"],
        diagnostic["reporting_start"],
        diagnostic["time_stamp_begin"],
        diagnostic["timestamp_begin"]
      ]
    else
      [
        period["end"],
        submitted_evidence["reporting_end"],
        diagnostic_period["end"],
        diagnostic["reporting_end"],
        diagnostic["time_stamp_end"],
        diagnostic["timestamp_end"]
      ]
    end
    candidates.filter_map { |value| parse_time(value) }.first
  end

  def default_source
    %w[android ios].include?(context["platform"].to_s.downcase) ? "sdk" : "api"
  end

  def evidence_kind_for(kind, source)
    return "aggregate_counter" if identity_scope_for(source) == "interval_aggregate"

    {
      "crash" => "crashed_stack",
      "native_crash" => "crashed_stack",
      "hang" => "sampled_call_tree",
      "cpu_exception" => "sampled_call_tree",
      "excessive_cpu" => "sampled_call_tree",
      "disk_write_exception" => "sampled_call_tree",
      "excessive_disk_writes" => "sampled_call_tree",
      "launch_failure" => "sampled_call_tree",
      "slow_launch" => "sampled_call_tree",
      "watchdog_termination" => "termination_metadata",
      "memory_termination" => "termination_metadata",
      "memory_limit_termination" => "memory_report",
      "memory_pressure_termination" => "memory_report"
    }.fetch(kind.to_s, "event_payload")
  end

  def identity_scope_for(source)
    %w[app_store_connect google_play aggregate].include?(source.to_s) ? "interval_aggregate" : "occurrence"
  end

  def fatality
    value = error_context["fatal"]
    return "fatal" if value == true
    return "nonfatal" if value == false

    "unknown"
  end

  def normalized_token(value)
    string = normalized_scalar(value)&.downcase&.tr(" -", "__")
    return if string.blank?

    string.gsub(/[^a-z0-9_.]/, "").first(80).presence
  end

  def normalized_scalar(value)
    return unless value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(Symbol)

    value.to_s.strip.first(128).presence
  end

  def positive_integer(value)
    integer = Integer(value, exception: false)
    integer if integer.to_i.positive?
  end

  def parse_time(value)
    return value.in_time_zone if value.respond_to?(:in_time_zone) && !value.is_a?(String)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def iso8601(value)
    value&.utc&.iso8601(6)
  end
end
