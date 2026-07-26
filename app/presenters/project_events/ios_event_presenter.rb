# frozen_string_literal: true

module ProjectEvents
  class IosEventPresenter
    include PayloadSupport

    FRAMEWORK_IMAGES = /\A(?:lib\S+|CoreFoundation|Foundation|UIKitCore|Swift|XCTest|dyld)\z/i

    attr_reader :event

    def initialize(event, exception_data = nil)
      @event = event
      @context = event_context_hash(event)
      @exception = normalize_hash(exception_data.presence || @context["exception"] || @context[:exception])
    end

    def exception_type
      scalar(@exception, "type") || scalar(@exception, "class") || "Unknown error"
    end

    def exception_message
      scalar(@exception, "message") || event&.message.to_s.presence
    end

    def mechanism
      nested_scalar("error", "mechanism") || scalar(@context, "error_mechanism") || (@exception.present? ? "handled_exception" : "unknown")
    end

    def mechanism_label
      {
        "handled_exception" => "Reported exception",
        "unhandled_exception" => "Fatal",
        "watchdog_termination" => "Watchdog termination",
        "native_crash" => "Native crash",
        "low_memory_kill" => "Low-memory exit"
      }.fetch(mechanism, "Reported exception")
    end

    def frames
      Array(@exception["stacktrace"] || @exception[:stacktrace] || @exception["backtrace"] || @exception[:backtrace]).filter_map.with_index do |raw, index|
        parse_frame(raw, index)
      end
    end

    def top_in_app_frame
      frames.find { |frame| frame[:application_frame] }
    end

    def app_details
      details(
        bundle_identifier: nested_scalar("app", "package_name") || scalar(@context, "bundle_identifier") || scalar(@context, "service"),
        version_name: nested_scalar("app", "version_name") || scalar(@context, "app_version"),
        version_code: nested_scalar("app", "version_code") || scalar(@context, "build_number"),
        release: scalar(@context, "release"),
        screen: nested_scalar("app", "screen") || scalar(@context, "screen_name")
      )
    end

    def device_details
      details(
        model: nested_scalar("device", "model") || scalar(@context, "device_model"),
        family: nested_scalar("device", "family") || scalar(@context, "device_family"),
        locale: nested_scalar("device", "locale") || scalar(@context, "locale")
      )
    end

    def os_details
      details(
        name: nested_scalar("os", "name") || scalar(@context, "os_name") || "iOS",
        version: nested_scalar("os", "version") || scalar(@context, "os_version")
      )
    end

    def correlation_details
      details(
        session: nested_scalar("session", "id") || scalar(@context, "session_id"),
        installation: nested_scalar("installation", "id_hash") || scalar(@context, "installation_id_hash"),
        user: scalar(@context, "user_id"),
        trace: scalar(@context, "trace_id")
      )
    end

    def breadcrumbs
      Array(@context["breadcrumbs"]).filter_map do |item|
        next unless item.is_a?(Hash)
        { timestamp: scalar(item, "timestamp"), category: scalar(item, "category") || "app", level: scalar(item, "level") || "info", message: scalar(item, "message"), data: item["data"].is_a?(Hash) ? item["data"] : {} }
      end
    end

    private

    def parse_frame(raw, index)
      if raw.is_a?(Hash)
        image = scalar(raw, "image") || scalar(raw, "module")
        symbol = scalar(raw, "symbol") || scalar(raw, "function") || scalar(raw, "method")
        address = scalar(raw, "address")
        file = scalar(raw, "file") || scalar(raw, "filename") || image
        line = scalar(raw, "line") || scalar(raw, "lineno")
      else
        match = /\A\s*\d+\s+(?<image>\S+)\s+(?<address>0x[0-9a-f]+)\s+(?<symbol>.+?)(?:\s+\+\s+\d+)?\s*\z/i.match(raw.to_s)
        return { raw: raw.to_s, image: nil, address: nil, class_name: nil, qualified_method: raw.to_s, method_name: raw.to_s, file: "Frame #{index}", line_number: nil, application_frame: index < 8 } unless match
        image = match[:image]
        address = match[:address]
        symbol = match[:symbol]
        file = image
        line = nil
      end

      {
        raw: raw,
        image: image,
        address: address,
        class_name: image,
        qualified_method: symbol,
        method_name: symbol,
        file: file,
        line_number: line.to_i.positive? ? line.to_i : nil,
        column_number: nil,
        code_context: nil,
        locals: {},
        absolute_path: nil,
        application_frame: image.present? && !image.match?(FRAMEWORK_IMAGES)
      }
    end

    def nested_scalar(parent, child)
      value = @context[parent]
      scalar(value, child) if value.is_a?(Hash)
    end

    def scalar(hash, key)
      return unless hash.is_a?(Hash)
      value = hash[key] || hash[key.to_sym]
      value.to_s.presence if value.is_a?(String) || value.is_a?(Numeric)
    end

    def details(values)
      values.reject { |_key, value| value.nil? || value.to_s.blank? }
    end
  end
end
