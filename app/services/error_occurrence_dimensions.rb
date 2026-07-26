# frozen_string_literal: true

require "openssl"

class ErrorOccurrenceDimensions
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
    "symbolication_status" => [ "symbolication", "status" ],
    "exception_type" => [ "exception", "type" ],
    "termination_namespace" => [ "termination", "namespace" ],
    "termination_code" => [ "termination", "code" ],
    "termination_reason" => [ "termination", "reason" ]
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
    if event.project.integration_ios?
      culprit = ProjectEvents::IosEventPresenter.new(event).top_in_app_frame&.dig(:method_name)
      values["culprit"] = culprit.to_s if culprit.present?
    end
    values
  end

  def release_identity
    version = context.dig("app", "version_name")
    build = context.dig("app", "version_code")
    [ version, build ].compact_blank.join("+").presence
  end

  def hashed_identifier(kind, value)
    return if value.blank?

    secret = Rails.application.secret_key_base
    OpenSSL::HMAC.hexdigest("SHA256", secret, "project:#{event.project_id}:#{kind}:#{value}")
  end
end
