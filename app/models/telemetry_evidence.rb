# frozen_string_literal: true

class TelemetryEvidence < Data.define(
  :schema_version,
  :source,
  :kind,
  :capture_mode,
  :evidence_kind,
  :identity_scope,
  :fatality,
  :time_precision,
  :occurred_at,
  :reporting_start,
  :reporting_end,
  :received_at,
  :producer,
  :normalization
)
  TIME_PRECISIONS = [ *TelemetryEvidenceNormalizer::TIME_PRECISIONS, "unknown" ].freeze

  class << self
    def for(event)
      context = event.context.is_a?(Hash) ? event.context.stringify_keys : {}
      evidence = context["telemetry_evidence"]
      return from_normalized(evidence) if evidence.is_a?(Hash)

      from_legacy(event, context)
    end

    private

    def from_normalized(value)
      evidence = value.stringify_keys
      time = evidence["time"].is_a?(Hash) ? evidence["time"].stringify_keys : {}
      precision = time["precision"].to_s.presence_in(TIME_PRECISIONS) || "unknown"

      new(
        schema_version: evidence["schema_version"].to_i,
        source: evidence["source"].to_s.presence || "unknown",
        kind: evidence["kind"].to_s.presence,
        capture_mode: evidence["capture_mode"].to_s.presence,
        evidence_kind: evidence["evidence_kind"].to_s.presence,
        identity_scope: evidence["identity_scope"].to_s.presence || "occurrence",
        fatality: evidence["fatality"].to_s.presence || "unknown",
        time_precision: precision,
        occurred_at: parse_time(time["occurred_at"]),
        reporting_start: parse_time(time["reporting_start"]),
        reporting_end: parse_time(time["reporting_end"]),
        received_at: parse_time(time["received_at"]),
        producer: evidence["producer"].is_a?(Hash) ? evidence["producer"].deep_dup.freeze : nil,
        normalization: evidence["normalization"].is_a?(Hash) ? evidence["normalization"].deep_dup.freeze : nil
      ).freeze
    end

    def from_legacy(event, context)
      diagnostic = context["diagnostic"].is_a?(Hash) ? context["diagnostic"].stringify_keys : {}
      new(
        schema_version: 0,
        source: diagnostic["source"].to_s.presence || legacy_source(context),
        kind: diagnostic["kind"].to_s.presence,
        capture_mode: nil,
        evidence_kind: nil,
        identity_scope: "occurrence",
        fatality: "unknown",
        time_precision: "unknown",
        occurred_at: event.occurred_at,
        reporting_start: nil,
        reporting_end: nil,
        received_at: event.created_at,
        producer: nil,
        normalization: nil
      ).freeze
    end

    def legacy_source(context)
      %w[android ios].include?(context["platform"].to_s.downcase) ? "sdk" : "api"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError, TypeError
      nil
    end
  end

  def exact_time?
    time_precision == "exact"
  end

  def reporting_interval?
    time_precision == "reporting_interval"
  end

  def received_only?
    time_precision == "received_only"
  end

  def operational_at
    received_at || reporting_end || occurred_at
  end
end
