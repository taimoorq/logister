# frozen_string_literal: true

require "openssl"
require "digest"
require "bigdecimal"

class ErrorOccurrenceDimensions
  MATERIALIZATION_VERSION = 2
  DIMENSION_PATHS = {
    "app_version" => [ "app", "version_name" ],
    "build_number" => [ "app", "version_code" ],
    "build_type" => [ "app", "build_type" ],
    "app_identifier" => [ "app", "identifier" ],
    "package_name" => [ "app", "package_name" ],
    "process_name" => [ "app", "process" ],
    "screen" => [ "app", "screen" ],
    "track" => [ "distribution", "track" ],
    "distribution_channel" => [ "distribution", "channel" ],
    "device_manufacturer" => [ "device", "manufacturer" ],
    "device_model" => [ "device", "model" ],
    "device_family" => [ "device", "family" ],
    "architecture" => [ "device", "architecture" ],
    "device_form_factor" => [ "device", "form_factor" ],
    "os_name" => [ "os", "name" ],
    "os_version" => [ "os", "version" ],
    "api_level" => [ "os", "api_level" ],
    "environment" => [ "environment" ],
    "apple_platform" => [ "apple_platform" ],
    "diagnostic_source" => [ "diagnostic", "source" ],
    "diagnostic_kind" => [ "diagnostic", "kind" ],
    "exception_type" => [ "exception", "type" ],
    "termination_namespace" => [ "termination", "namespace" ],
    "termination_code" => [ "termination", "code" ],
    "termination_reason" => [ "termination", "reason" ],
    "evidence_source" => [ "telemetry_evidence", "source" ],
    "evidence_kind" => [ "telemetry_evidence", "evidence_kind" ],
    "time_precision" => [ "telemetry_evidence", "time", "precision" ],
    "identity_scope" => [ "telemetry_evidence", "identity_scope" ],
    "capture_mode" => [ "telemetry_evidence", "capture_mode" ],
    "fatality" => [ "telemetry_evidence", "fatality" ],
    "reporting_start_at" => [ "telemetry_evidence", "time", "reporting_start" ],
    "reporting_end_at" => [ "telemetry_evidence", "time", "reporting_end" ],
    "session_started_at" => [ "session", "started_at" ]
  }.freeze

  attr_reader :event, :context

  def initialize(event)
    @event = event
    @context = MobileTelemetryNormalizer.normalize(event.context)
  end

  def attributes
    return {} unless event.project.integration_android? || event.project.integration_ios?

    {
      mechanism: context.dig("error", "mechanism"),
      release: context["release"].presence || release_identity,
      session_hash: hashed_identifier(:session, context.dig("session", "id")),
      installation_hash: hashed_identifier(:installation, context.dig("installation", "id_hash")),
      user_hash: hashed_identifier(:user, context["user_id"]),
      foreground: context.dig("app", "in_foreground"),
      telemetry_schema_version: context["telemetry_schema_version"],
      dimensions: dimensions
    }
  end

  private

  def dimensions
    values = DIMENSION_PATHS.each_with_object({}) do |(key, path), result|
      value = context.dig(*path)
      result[key] = value.to_s if value.present? || value == false
    end
    values["materialization_version"] = MATERIALIZATION_VERSION.to_s
    session_age_ms = exact_session_age_ms
    values["session_age_ms"] = session_age_ms.to_s if session_age_ms
    if event.project.integration_ios?
      values.merge!(diagnostic_measurement_dimensions)
      enrichment = event.project.mobile_event_enrichments.apple_symbolication.find_by(event_uuid: event.uuid)
      presenter = ProjectEvents::IosEventPresenter.new(event, enrichment:)
      values.merge!(mobile_variant_dimensions(presenter, platform: :ios))
      culprit = presenter.top_in_app_frame&.dig(:method_name)
      values["culprit"] = culprit.to_s if culprit.present?
      values["symbolication_status"] = AppleSymbolCoverage.call(
        project: event.project,
        event: event,
        presenter: presenter,
        enrichment:
      ).status.to_s
    elsif event.project.integration_android?
      presenter = ProjectEvents::AndroidEventPresenter.new(event)
      values.merge!(mobile_variant_dimensions(presenter, platform: :android))
      app = context.fetch("app", {})
      mapping = if app["package_name"].present? && app["version_code"].present?
        event.project.android_mapping_files.find_by(package_name: app["package_name"], version_code: app["version_code"].to_s)
      end
      values["mapping_status"] = if app["version_code"].blank?
        "build_unknown"
      elsif mapping
        "mapping_matched"
      else
        "missing"
      end
    end
    values
  end

  def release_identity
    version = context.dig("app", "version_name")
    build = context.dig("app", "version_code")
    [ version, build ].compact_blank.join("+").presence
  end

  def exact_session_age_ms
    evidence = TelemetryEvidence.for(event)
    return unless evidence.exact_time?

    started_at = Time.zone.parse(context.dig("session", "started_at").to_s)
    occurred_at = evidence.occurred_at || event.occurred_at
    return unless started_at && occurred_at

    age_ms = ((occurred_at - started_at) * 1_000).round
    age_ms if age_ms.between?(0, 7.days.in_milliseconds)
  rescue ArgumentError, TypeError
    nil
  end

  def diagnostic_measurement_dimensions
    measurements = context.dig("diagnostic", "measurements")
    return {} unless measurements.is_a?(Hash)

    key = case context.dig("diagnostic", "kind")
    when "hang" then "hang_duration"
    when "cpu_exception", "excessive_cpu" then "total_cpu_time"
    when "disk_write_exception", "excessive_disk_writes" then "total_bytes_written"
    when "launch_failure", "slow_launch" then "launch_duration"
    end
    measurement = measurements[key]
    return {} unless key && measurement.is_a?(Hash)

    value = Float(measurement["value"] || measurement[:value], exception: false)
    unit = (measurement["unit"] || measurement[:unit]).to_s
    return {} unless value&.finite? && value >= 0 && unit.present?

    {
      "diagnostic_measurement" => key,
      "diagnostic_measurement_value" => value.to_s,
      "diagnostic_measurement_unit" => unit.first(24)
    }
  end

  def mobile_variant_dimensions(presenter, platform:)
    frames = Array(presenter.all_frames).select { |frame| frame[:application_frame] }.first(8)
    identities = frames.filter_map do |frame|
      if platform == :ios
        uuid = frame[:image_uuid].to_s.delete("{}").upcase.presence
        offset = canonical_address(frame[:relative_address])
        (uuid && offset && "#{uuid}@#{offset}") || frame[:symbol_identity].to_s.presence
      else
        [ frame[:class_name], frame[:method_name] ].compact_blank.join("#").presence
      end
    end
    return {} if identities.size < 2

    labels = frames.filter_map { |frame| frame[:method_name].to_s.presence }.first(3)
    {
      "variant_key" => Digest::SHA256.hexdigest([ platform, context.dig("diagnostic", "kind"), context.dig("error", "mechanism"), identities ].to_json),
      "variant_label" => labels.join(" → ").first(160).presence || "#{identities.size}-frame app path",
      "variant_frame_count" => identities.size.to_s
    }.compact
  end

  def canonical_address(value)
    string = value.to_s.strip
    integer = if string.match?(/\A0x[0-9a-f]+\z/i)
      Integer(string)
    elsif string.match?(/\A\d+(?:\.0+)?\z/)
      BigDecimal(string).to_i
    end
    "0x#{integer.to_s(16)}" if integer && integer >= 0
  rescue ArgumentError
    nil
  end

  def hashed_identifier(kind, value)
    return if value.blank?

    secret = Rails.application.secret_key_base
    OpenSSL::HMAC.hexdigest("SHA256", secret, "project:#{event.project_id}:#{kind}:#{value}")
  end
end
