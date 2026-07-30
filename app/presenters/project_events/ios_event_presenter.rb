# frozen_string_literal: true

module ProjectEvents
  class IosEventPresenter
    include PayloadSupport

    FRAMEWORK_IMAGES = /\A(?:lib\S+|CoreFoundation|Foundation|UIKitCore|AppKit|Swift\S*|XCTest\S*|dyld|Dispatch|CFNetwork|CoreGraphics|QuartzCore|Metal\S*)\z/i
    MECHANISM_LABELS = {
      "handled_exception" => "Reported error",
      "unhandled_exception" => "Fatal crash",
      "native_crash" => "Native crash",
      "hang" => "Hang",
      "watchdog_termination" => "Watchdog termination",
      "memory_termination" => "Memory termination",
      "low_memory_kill" => "Memory termination",
      "disk_write_exception" => "Disk-write diagnostic",
      "launch_failure" => "Launch failure",
      "unknown" => "Apple diagnostic"
    }.freeze
    DIAGNOSTIC_KIND_LABELS = {
      "reported_error" => "Reported error",
      "crash" => "Crash",
      "hang" => "Hang",
      "watchdog" => "Watchdog termination",
      "watchdog_termination" => "Watchdog termination",
      "memory_termination" => "Memory termination",
      "disk_write_exception" => "Disk-write diagnostic",
      "launch_failure" => "Launch failure"
    }.freeze
    SYMBOLICATION_LABELS = {
      "not_required" => "Symbols included",
      "pending" => "Symbolication pending",
      "symbolicated" => "Symbolicated",
      "partial" => "Partially symbolicated",
      "missing" => "dSYM missing",
      "failed" => "Symbolication failed",
      "unknown" => "Symbol status unknown"
    }.freeze
    CAPTURE_SOURCE_LABELS = {
      "manual" => "Manual capture",
      "metrickit" => "MetricKit capture"
    }.freeze

    attr_reader :event, :context, :exception

    def initialize(event, exception_data = nil)
      @event = event
      @context = MobileTelemetryNormalizer.normalize(event_context_hash(event))
      @exception = normalize_hash(exception_data.presence || @context["exception"])
    end

    def exception_type
      scalar(exception, "type") || scalar(exception, "class") || termination_details[:reason] || "Unknown error"
    end

    def exception_message
      scalar(exception, "message") || event&.message.to_s.presence
    end

    def mechanism
      value = nested_scalar("error", "mechanism") || scalar(context, "error_mechanism")
      value ||= "handled_exception" if exception.present?
      MECHANISM_LABELS.key?(value) ? value : "unknown"
    end

    def mechanism_label
      MECHANISM_LABELS.fetch(mechanism)
    end

    def diagnostic_source
      nested_scalar("diagnostic", "source") || "unknown"
    end

    def diagnostic_source_label
      { "sdk" => "Logister SDK", "metrickit" => "MetricKit", "app_store" => "App Store Connect" }.fetch(diagnostic_source, "Source not reported")
    end

    def capture_source
      nested_scalar("error", "capture_source") || scalar(context, "capture_source")
    end

    def capture_source_label
      CAPTURE_SOURCE_LABELS[capture_source]
    end

    def exception_data_policy
      nested_scalar("error", "data_policy") || scalar(context, "exception_data_policy")
    end

    def exception_detail_redacted?
      exception_data_policy == "type_and_stacktrace"
    end

    def diagnostic_kind
      nested_scalar("diagnostic", "kind") || mechanism
    end

    def diagnostic_kind_label
      DIAGNOSTIC_KIND_LABELS.fetch(diagnostic_kind, mechanism_label)
    end

    def handled?
      boolean_value(nested_value("error", "handled"), default: mechanism == "handled_exception")
    end

    def fatal?
      boolean_value(nested_value("error", "fatal"), default: %w[unhandled_exception native_crash].include?(mechanism))
    end

    def user_perceived?
      boolean_value(nested_value("error", "user_perceived"), default: false)
    end

    def threads
      value = exception["threads"] || exception[:threads] || context["threads"] || context[:threads]
      normalized = Array(value).filter_map.with_index { |thread, index| normalize_thread(thread, index) }
      return normalized if normalized.present?

      stack = normalize_frames(exception["stacktrace"] || exception[:stacktrace] || exception["backtrace"] || exception[:backtrace])
      stack.present? ? [ { id: "reported-thread", name: "Reporting thread", triggered: true, frames: stack } ] : []
    end

    def triggered_thread
      threads.find { |thread| thread[:triggered] } || threads.first
    end

    def other_threads
      selected = triggered_thread
      threads.reject { |thread| thread.equal?(selected) || thread[:id] == selected&.dig(:id) }
    end

    def frames
      triggered_thread&.fetch(:frames, []) || []
    end

    def all_frames
      threads.flat_map { |thread| thread[:frames] }
    end

    def top_in_app_frame
      frames.find { |frame| frame[:application_frame] } || all_frames.find { |frame| frame[:application_frame] }
    end

    def frame_text(frame)
      raw = frame[:raw]
      return raw if raw.is_a?(String) && raw.present?

      [ frame[:image], frame[:address] || frame[:relative_address], frame[:qualified_method] ].compact_blank.join(" ")
    end

    def stacktrace_text
      threads.flat_map do |thread|
        [ "#{thread[:triggered] ? 'Triggered' : 'Thread'}: #{thread[:name]}", *thread[:frames].map { |frame| "  #{frame_text(frame)}" } ]
      end.join("\n")
    end

    def binary_images
      value = exception["binary_images"] || exception[:binary_images] || context["binary_images"] || context[:binary_images]
      Array(value).filter_map do |image|
        next unless image.is_a?(Hash)

        details(
          name: scalar(image, "name") || scalar(image, "image") || scalar(image, "path"),
          uuid: scalar(image, "uuid") || scalar(image, "image_uuid"),
          architecture: scalar(image, "architecture") || scalar(image, "arch"),
          base_address: scalar(image, "base_address") || scalar(image, "address"),
          size: scalar(image, "size")
        )
      end
    end

    def symbolication_status
      value = nested_scalar("symbolication", "status") || "unknown"
      SYMBOLICATION_LABELS.key?(value) ? value : "unknown"
    end

    def symbolication_label
      SYMBOLICATION_LABELS.fetch(symbolication_status)
    end

    def missing_symbol_uuids
      Array(nested_value("symbolication", "missing_uuids")).map(&:to_s).compact_blank
    end

    def termination_details
      termination = normalize_hash(context["termination"])
      details(
        namespace: scalar(termination, "namespace"),
        code: scalar(termination, "code"),
        reason: scalar(termination, "reason"),
        process: scalar(termination, "process"),
        visibility: scalar(termination, "visibility")
      )
    end

    def diagnostic_details
      details(
        source: diagnostic_source_label,
        kind: diagnostic_kind_label,
        external_id: nested_scalar("diagnostic", "external_id"),
        occurred_at: nested_scalar("diagnostic", "occurred_at"),
        signature: nested_scalar("diagnostic", "signature")
      )
    end

    def app_details
      details(
        bundle_identifier: nested_scalar("app", "identifier") || nested_scalar("app", "package_name") || scalar(context, "bundle_identifier") || scalar(context, "service"),
        version_name: nested_scalar("app", "version_name") || scalar(context, "app_version"),
        version_code: nested_scalar("app", "version_code") || scalar(context, "build_number"),
        release: scalar(context, "release"),
        distribution_channel: nested_scalar("distribution", "channel") || nested_scalar("distribution", "track"),
        process: nested_scalar("app", "process"),
        screen: nested_scalar("app", "screen") || scalar(context, "screen_name"),
        in_foreground: nested_value("app", "in_foreground")
      )
    end

    def device_details
      details(
        model: nested_scalar("device", "model") || scalar(context, "device_model"),
        family: nested_scalar("device", "family") || scalar(context, "device_family"),
        architecture: nested_scalar("device", "architecture"),
        locale: nested_scalar("device", "locale") || scalar(context, "locale")
      )
    end

    def os_details
      details(
        platform: scalar(context, "apple_platform")&.upcase,
        name: nested_scalar("os", "name") || scalar(context, "os_name") || "iOS",
        version: nested_scalar("os", "version") || scalar(context, "ios_version") || scalar(context, "os_version"),
        build: nested_scalar("os", "build") || scalar(context, "os_build")
      )
    end

    def correlation_details
      details(
        session: nested_scalar("session", "id") || scalar(context, "session_id"),
        installation: nested_scalar("installation", "id_hash") || scalar(context, "installation_id_hash"),
        user: scalar(context, "user_id"),
        trace: scalar(context, "trace_id")
      )
    end

    def breadcrumbs
      Array(context["breadcrumbs"]).filter_map do |item|
        next unless item.is_a?(Hash)

        {
          timestamp: scalar(item, "timestamp") || scalar(item, "occurred_at"),
          category: scalar(item, "category") || "app",
          level: scalar(item, "level") || "info",
          message: scalar(item, "message"),
          data: normalize_hash(item["data"] || item[:data])
        }
      end
    end

    def telemetry_schema_version
      scalar(context, "telemetry_schema_version")&.to_i
    end

    private

    def normalize_thread(raw, index)
      return unless raw.is_a?(Hash)

      frames = normalize_frames(raw["frames"] || raw[:frames] || raw["stacktrace"] || raw[:stacktrace])
      {
        id: scalar(raw, "id") || scalar(raw, "number") || index.to_s,
        name: scalar(raw, "name") || "Thread #{index}",
        triggered: boolean_value(raw["triggered"] || raw[:triggered] || raw["crashed"] || raw[:crashed], default: false),
        frames: frames
      }
    end

    def normalize_frames(value)
      Array(value).filter_map.with_index { |raw, index| parse_frame(raw, index) }
    end

    def parse_frame(raw, index)
      if raw.is_a?(Hash)
        image = scalar(raw, "image") || scalar(raw, "module") || scalar(raw, "binary")
        symbol = scalar(raw, "symbol") || scalar(raw, "function") || scalar(raw, "method") || scalar(raw, "name")
        address = scalar(raw, "address") || scalar(raw, "instruction_addr")
        relative_address = scalar(raw, "relative_address") || scalar(raw, "image_offset")
        image_uuid = scalar(raw, "image_uuid") || scalar(raw, "binary_uuid") || scalar(raw, "uuid")
        file = scalar(raw, "file") || scalar(raw, "filename") || image
        line = scalar(raw, "line") || scalar(raw, "lineno") || scalar(raw, "line_number")
        column = scalar(raw, "column") || scalar(raw, "column_number")
        explicit_in_app = raw["application_frame"] || raw[:application_frame] || raw["in_app"] || raw[:in_app]
      else
        match = /\A\s*\d+\s+(?<image>\S+)\s+(?<address>0x[0-9a-f]+)\s+(?<symbol>.+?)(?:\s+\+\s+\d+)?\s*\z/i.match(raw.to_s)
        return fallback_frame(raw, index) unless match

        image = match[:image]
        address = match[:address]
        symbol = match[:symbol]
        relative_address = nil
        image_uuid = nil
        file = image
        line = nil
        column = nil
        explicit_in_app = nil
      end

      symbol_identity = symbol.to_s.sub(/\s+\+\s+\d+\z/, "").presence
      {
        raw: raw,
        image: image,
        image_uuid: image_uuid,
        address: address,
        relative_address: relative_address,
        class_name: image,
        qualified_method: symbol,
        symbol_identity: symbol_identity,
        method_name: symbol_identity,
        file: file,
        line_number: line.to_i.positive? ? line.to_i : nil,
        column_number: column.to_i.positive? ? column.to_i : nil,
        code_context: scalar(raw, "code_context") || scalar(raw, "source"),
        locals: raw.is_a?(Hash) ? normalize_hash(raw["locals"] || raw[:locals]) : {},
        absolute_path: nil,
        application_frame: application_frame?(image, explicit_in_app)
      }
    end

    def fallback_frame(raw, index)
      {
        raw: raw.to_s,
        image: nil,
        image_uuid: nil,
        address: nil,
        relative_address: nil,
        class_name: nil,
        qualified_method: raw.to_s,
        symbol_identity: nil,
        method_name: raw.to_s,
        file: "Frame #{index}",
        line_number: nil,
        column_number: nil,
        code_context: nil,
        locals: {},
        absolute_path: nil,
        application_frame: false
      }
    end

    def application_frame?(image, explicit)
      return boolean_value(explicit, default: false) unless explicit.nil?

      image.present? && !image.match?(FRAMEWORK_IMAGES)
    end

    def nested_value(parent, child)
      value = context[parent] || context[parent.to_sym]
      return unless value.is_a?(Hash)

      value[child] || value[child.to_sym]
    end

    def nested_scalar(parent, child)
      value = nested_value(parent, child)
      value.to_s.presence if value.is_a?(String) || value.is_a?(Numeric)
    end

    def scalar(hash, key)
      return unless hash.is_a?(Hash)

      value = hash[key] || hash[key.to_sym]
      value.to_s.presence if value.is_a?(String) || value.is_a?(Numeric)
    end

    def boolean_value(value, default:)
      return default if value.nil?
      return value if value == true || value == false

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def details(values)
      values.reject { |_key, value| value.nil? || (value.respond_to?(:blank?) && value.blank?) }
    end
  end
end
