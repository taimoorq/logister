# frozen_string_literal: true

class MobileTelemetryNormalizer
  MAX_BREADCRUMBS = 100
  MAX_FEATURE_FLAGS = 50
  SENSITIVE_KEYS = %w[
    advertising_id advertisingId android_id androidId device_serial deviceSerial
    hardware_serial hardwareSerial imei meid serial subscriber_id subscriberId
  ].freeze

  class << self
    def normalize(context)
      normalized = context.is_a?(Hash) ? context.deep_dup.stringify_keys : {}
      strip_sensitive_keys!(normalized)

      case normalized["platform"].to_s.downcase
      when "android" then normalize_android!(normalized)
      when "ios" then normalize_ios!(normalized)
      end

      normalized
    end

    private

    def normalize_android!(context)
      context["platform"] = "android"
      context["telemetry_schema_version"] = positive_integer(context["telemetry_schema_version"]) || 1

      merge_object!(context, "app", {
        "package_name" => first(context.dig("app", "package_name"), context["package_name"], context["service"]),
        "version_name" => first(context.dig("app", "version_name"), context["app_version"]),
        "version_code" => first(context.dig("app", "version_code"), context["build_number"]),
        "build_type" => first(context.dig("app", "build_type"), context["build_type"]),
        "screen" => first(context.dig("app", "screen"), context["screen_name"]),
        "in_foreground" => boolean(context.dig("app", "in_foreground"), context["in_foreground"])
      })
      merge_object!(context, "device", {
        "manufacturer" => first(context.dig("device", "manufacturer"), context["device_manufacturer"]),
        "brand" => first(context.dig("device", "brand"), context["device_brand"]),
        "model" => first(context.dig("device", "model"), context["device_model"]),
        "form_factor" => first(context.dig("device", "form_factor"), context["device_form_factor"]),
        "locale" => first(context.dig("device", "locale"), context["locale"])
      })
      merge_object!(context, "os", {
        "name" => first(context.dig("os", "name"), context["os_name"], "Android"),
        "version" => first(context.dig("os", "version"), context["os_version"]),
        "api_level" => first(context.dig("os", "api_level"), context["android_api_level"])
      })
      merge_object!(context, "distribution", {
        "track" => first(context.dig("distribution", "track"), context["distribution_track"])
      })
      merge_object!(context, "session", {
        "id" => first(context.dig("session", "id"), context["session_id"])
      })
      merge_object!(context, "installation", {
        "id_hash" => first(context.dig("installation", "id_hash"), context["installation_id_hash"])
      })

      exception_present = context["exception"].is_a?(Hash)
      mechanism = first(context.dig("error", "mechanism"), context["error_mechanism"])
      mechanism = "handled_exception" if mechanism.blank? && exception_present
      merge_object!(context, "error", {
        "mechanism" => mechanism,
        "handled" => boolean(context.dig("error", "handled"), context["handled"], exception_present ? true : nil),
        "user_perceived" => boolean(context.dig("error", "user_perceived"), context["user_perceived"])
      })

      context["breadcrumbs"] = normalize_breadcrumbs(context["breadcrumbs"])
      context["feature_flags"] = normalize_feature_flags(context["feature_flags"])
    end

    def normalize_ios!(context)
      context["platform"] = "ios"
      context["telemetry_schema_version"] = positive_integer(context["telemetry_schema_version"]) || 1
      merge_object!(context, "app", {
        "package_name" => first(context.dig("app", "package_name"), context["bundle_identifier"], context["service"]),
        "version_name" => first(context.dig("app", "version_name"), context["app_version"]),
        "version_code" => first(context.dig("app", "version_code"), context["build_number"]),
        "screen" => first(context.dig("app", "screen"), context["screen_name"]),
        "in_foreground" => boolean(context.dig("app", "in_foreground"), context["in_foreground"])
      })
      merge_object!(context, "device", {
        "model" => first(context.dig("device", "model"), context["device_model"]),
        "family" => first(context.dig("device", "family"), context["device_family"]),
        "locale" => first(context.dig("device", "locale"), context["locale"])
      })
      merge_object!(context, "os", {
        "name" => first(context.dig("os", "name"), context["os_name"], "iOS"),
        "version" => first(context.dig("os", "version"), context["os_version"])
      })
      merge_object!(context, "session", { "id" => first(context.dig("session", "id"), context["session_id"]) })
      merge_object!(context, "installation", { "id_hash" => first(context.dig("installation", "id_hash"), context["installation_id_hash"]) })

      exception_present = context["exception"].is_a?(Hash)
      merge_object!(context, "error", {
        "mechanism" => first(context.dig("error", "mechanism"), context["error_mechanism"], exception_present ? "handled_exception" : nil),
        "handled" => boolean(context.dig("error", "handled"), context["handled"], exception_present ? true : nil),
        "user_perceived" => boolean(context.dig("error", "user_perceived"), context["user_perceived"])
      })

      context["breadcrumbs"] = normalize_breadcrumbs(context["breadcrumbs"])
      context["feature_flags"] = normalize_feature_flags(context["feature_flags"])
    end

    def merge_object!(context, key, values)
      existing = context[key].is_a?(Hash) ? context[key].stringify_keys : {}
      values.each { |name, value| existing[name] = value unless value.nil? }
      context[key] = existing unless existing.empty?
    end

    def normalize_breadcrumbs(value)
      Array(value).last(MAX_BREADCRUMBS).filter_map do |entry|
        next unless entry.is_a?(Hash)

        normalized = entry.stringify_keys.slice("timestamp", "occurred_at", "category", "level", "message", "data")
        normalized["data"] = normalized["data"].stringify_keys.first(20).to_h if normalized["data"].is_a?(Hash)
        normalized
      end
    end

    def normalize_feature_flags(value)
      case value
      when Hash then value.stringify_keys.first(MAX_FEATURE_FLAGS).to_h
      when Array then value.first(MAX_FEATURE_FLAGS)
      else []
      end
    end

    def strip_sensitive_keys!(value)
      case value
      when Hash
        SENSITIVE_KEYS.each { |key| value.delete(key) }
        value.each_value { |nested| strip_sensitive_keys!(nested) }
      when Array
        value.each { |nested| strip_sensitive_keys!(nested) }
      end
    end

    def first(*values)
      values.find { |value| !value.nil? && !(value.respond_to?(:blank?) && value.blank?) }
    end

    def boolean(*values)
      value = values.find { |candidate| !candidate.nil? }
      return if value.nil?
      return value if value == true || value == false

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def positive_integer(value)
      integer = Integer(value, exception: false)
      integer if integer.to_i.positive?
    end
  end
end
