# frozen_string_literal: true

require "openssl"

class ErrorOccurrenceDimensions
  DIMENSION_PATHS = {
    "app_version" => [ "app", "version_name" ],
    "build_number" => [ "app", "version_code" ],
    "build_type" => [ "app", "build_type" ],
    "package_name" => [ "app", "package_name" ],
    "screen" => [ "app", "screen" ],
    "track" => [ "distribution", "track" ],
    "device_manufacturer" => [ "device", "manufacturer" ],
    "device_model" => [ "device", "model" ],
    "device_form_factor" => [ "device", "form_factor" ],
    "os_name" => [ "os", "name" ],
    "os_version" => [ "os", "version" ],
    "api_level" => [ "os", "api_level" ],
    "environment" => [ "environment" ]
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
    DIMENSION_PATHS.each_with_object({}) do |(key, path), values|
      value = context.dig(*path)
      values[key] = value.to_s if value.present? || value == false
    end
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
