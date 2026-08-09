# frozen_string_literal: true

module ProjectEvents
  class IosEventPresenter
    include PayloadSupport

    FRAMEWORK_IMAGES = /\A(?:lib\S+|CoreFoundation|Foundation|UIKitCore|AppKit|Swift\S*|XCTest\S*|dyld|Dispatch|CFNetwork|CoreGraphics|QuartzCore|Metal\S*)\z/i
    MECHANISM_LABELS = {
      "handled_exception" => "Reported error",
      "unhandled_exception" => "Unhandled exception",
      "native_crash" => "Native crash",
      "hang" => "Hang",
      "resource_diagnostic" => "Resource diagnostic",
      "performance_diagnostic" => "Performance diagnostic",
      "watchdog_termination" => "Watchdog termination",
      "memory_termination" => "Memory termination",
      "low_memory_kill" => "Memory termination",
      "disk_write_exception" => "Excessive disk writes",
      "launch_failure" => "Slow app launch",
      "unknown" => "Apple diagnostic"
    }.freeze
    DIAGNOSTIC_KIND_LABELS = {
      "reported_error" => "Reported error",
      "crash" => "Crash",
      "hang" => "Hang",
      "cpu_exception" => "Excessive CPU",
      "excessive_cpu" => "Excessive CPU",
      "watchdog" => "Watchdog termination",
      "watchdog_termination" => "Watchdog termination",
      "memory_termination" => "Memory termination",
      "memory_limit_termination" => "Memory-limit termination",
      "memory_pressure_termination" => "Memory-pressure termination",
      "nonfatal_resource_diagnostic" => "Resource diagnostic",
      "disk_write_exception" => "Excessive disk writes",
      "excessive_disk_writes" => "Excessive disk writes",
      "launch_failure" => "Slow app launch",
      "slow_launch" => "Slow app launch",
      "aggregate_exit_metric" => "Aggregate exit metric"
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

    attr_reader :event, :context, :exception, :enrichment

    def initialize(event, exception_data = nil, enrichment: nil)
      @event = event
      @context = MobileTelemetryNormalizer.normalize(event_context_hash(event))
      @exception = normalize_hash(exception_data.presence || @context["exception"])
      @enrichment = enrichment
      @derived_frames_by_identity = Array(enrichment&.data&.dig("frames")).index_by { |frame| frame_identity(frame) }
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

    def failure_type_label
      diagnostic_kind_label
    end

    def technical_signature
      frame = top_in_app_frame
      culprit = frame&.dig(:qualified_method).presence || frame&.dig(:method_name).presence
      identity = if %w[reported_error crash].include?(diagnostic_kind)
        exception_type.presence || diagnostic_kind_label
      else
        diagnostic_kind_label
      end
      signature = [ identity, culprit.present? && "in #{culprit}" ].compact_blank.join(" ")
      [ signature.presence, measurement_summary ].compact_blank.join(" · ").presence || termination_details[:reason] || event&.message.to_s.presence
    end

    def culprit_location
      frame = top_in_app_frame
      return if frame.blank?

      location = frame[:file].presence
      location = "#{location}:#{frame[:line_number]}" if location && frame[:line_number]
      location
    end

    def measurement_summary
      diagnostic = normalize_hash(context["diagnostic"])
      measurements = normalize_hash(diagnostic["measurements"] || context["measurements"])
      candidates = case diagnostic_kind
      when "hang"
        typed = typed_measurement(measurements, "hang_duration")
        typed ? [ "#{format_duration(typed[:value], typed[:unit])} hang" ] :
          legacy_measurements([ [ measurements["duration_ms"] || diagnostic["duration_ms"], "ms hang" ], [ measurements["duration_seconds"] || diagnostic["duration_seconds"], "s hang" ] ])
      when "cpu_exception", "excessive_cpu"
        cpu = typed_measurement(measurements, "total_cpu_time")
        sampled = typed_measurement(measurements, "sampled_time")
        typed = [ cpu && "#{format_duration(cpu[:value], cpu[:unit])} CPU", sampled && "#{format_duration(sampled[:value], sampled[:unit])} sampled" ].compact
        typed.presence || legacy_measurements([ [ measurements["total_cpu_time_seconds"] || diagnostic["total_cpu_time_seconds"], "s CPU" ], [ measurements["sampled_time_seconds"] || diagnostic["sampled_time_seconds"], "s sampled" ] ])
      when "disk_write_exception", "excessive_disk_writes"
        typed = typed_measurement(measurements, "total_bytes_written")
        typed ? [ "#{format_bytes(typed[:value], typed[:unit])} written" ] :
          legacy_measurements([ [ measurements["total_bytes_written"] || diagnostic["total_bytes_written"], "bytes written" ] ])
      when "launch_failure", "slow_launch"
        typed = typed_measurement(measurements, "launch_duration")
        typed ? [ "#{format_duration(typed[:value], typed[:unit])} launch" ] :
          legacy_measurements([ [ measurements["duration_ms"] || diagnostic["duration_ms"], "ms launch" ] ])
      else
        []
      end
      Array(candidates).compact_blank.join(" · ").presence
    end

    def measurement_details
      summary = measurement_summary
      summary.present? ? { summary: } : {}
    end

    def call_stack_tree
      diagnostic = normalize_hash(context["diagnostic"])
      tree = normalize_hash(diagnostic["call_stack_tree"])
      stacks = Array(tree["stacks"]).filter_map.with_index do |stack, index|
        next unless stack.is_a?(Hash)

        {
          id: scalar(stack, "id") || index.to_s,
          name: scalar(stack, "name") || "Call path #{index + 1}",
          role: scalar(stack, "role") || "sampled",
          attributed: boolean_value(stack["attributed"] || stack[:attributed], default: false),
          sample_count: positive_number(stack["sample_count"] || stack[:sample_count]),
          root_frames: Array(stack["root_frames"] || stack[:root_frames]).first(100).filter_map { |frame| normalize_tree_frame(frame, depth: 0) }
        }
      end
      return {} if stacks.empty?

      { per_thread: boolean_value(tree["per_thread"] || tree[:per_thread], default: false), stacks: }
    end

    def handled?
      boolean_value(nested_value("error", "handled"), default: mechanism == "handled_exception")
    end

    def fatal?
      explicit = nested_value("error", "fatal")
      return boolean_value(explicit, default: false) unless explicit.nil?
      return false if %w[hang cpu_exception excessive_cpu disk_write_exception excessive_disk_writes launch_failure slow_launch nonfatal_resource_diagnostic aggregate_exit_metric].include?(diagnostic_kind)

      %w[crash watchdog watchdog_termination memory_limit_termination memory_pressure_termination].include?(diagnostic_kind) || %w[unhandled_exception native_crash].include?(mechanism)
    end

    def user_perceived?
      boolean_value(nested_value("error", "user_perceived"), default: false)
    end

    def threads
      value = exception["threads"] || exception[:threads] || context["threads"] || context[:threads]
      normalized = Array(value).filter_map.with_index { |thread, index| normalize_thread(thread, index) }
      return normalized if normalized.present?

      stack = normalize_frames(exception["stacktrace"] || exception[:stacktrace] || exception["backtrace"] || exception[:backtrace])
      stack.present? ? [ { id: "reported-thread", name: "Reporting thread", role: "reporting", triggered: false, frames: stack } ] : []
    end

    def triggered_thread
      threads.find { |thread| thread[:triggered] } || threads.first
    end

    def other_threads
      selected = triggered_thread
      threads.reject { |thread| thread.equal?(selected) || thread[:id] == selected&.dig(:id) }
    end

    def selected_thread_role_label
      {
        "reporting" => "Reporting thread",
        "crashed" => "Crashed thread",
        "attributed" => "Attributed stack",
        "main" => "Main thread",
        "sampled" => "Sampled call path",
        "unknown" => "Selected thread"
      }.fetch(triggered_thread&.dig(:role).to_s, "Selected thread")
    end

    def stack_not_applicable?
      frames.empty? && %w[memory_termination memory_limit_termination memory_pressure_termination aggregate_exit_metric].include?(diagnostic_kind)
    end

    def stack_unavailable_reason
      return unless stack_not_applicable?

      if diagnostic_kind == "aggregate_exit_metric"
        "This record is an interval aggregate, not an individual stack-bearing occurrence."
      else
        "This memory/termination evidence does not include an app call stack; use the termination and memory facts instead."
      end
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
        [ "#{thread[:role].to_s.humanize.presence || 'Thread'}: #{thread[:name]}", *thread[:frames].map { |frame| "  #{frame_text(frame)}" } ]
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
      if enrichment&.status == "complete" && @derived_frames_by_identity.any?
        return "symbolicated"
      elsif enrichment&.status == "partial"
        return "partial"
      elsif enrichment&.status == "failed"
        return "failed"
      end

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
        session: masked_identifier(nested_scalar("session", "id") || scalar(context, "session_id")),
        installation: masked_identifier(nested_scalar("installation", "id_hash") || scalar(context, "installation_id_hash")),
        user: masked_identifier(scalar(context, "user_id")),
        trace: masked_identifier(scalar(context, "trace_id"))
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

    def typed_measurement(measurements, key)
      value = normalize_hash(measurements[key])
      number = positive_number(value["value"])
      unit = scalar(value, "unit")
      return unless number && unit.present?

      { value: number, unit: unit.downcase }
    end

    def legacy_measurements(values)
      values.filter_map do |value, suffix|
        next if value.blank?

        "#{value} #{suffix}"
      end
    end

    def format_duration(value, unit)
      return "#{format_number(value)} #{unit}" unless unit == "seconds"
      return "#{format_number(value * 1_000)} ms" if value.positive? && value < 1

      "#{format_number(value)} s"
    end

    def format_bytes(value, unit)
      return "#{format_number(value)} #{unit}" unless unit == "bytes"

      ActiveSupport::NumberHelper.number_to_human_size(value, precision: 3, strip_insignificant_zeros: true)
    end

    def format_number(value)
      value.to_i == value ? value.to_i.to_s : value.round(2).to_s
    end

    def positive_number(value)
      number = Float(value, exception: false)
      number if number&.finite? && number >= 0
    end

    def normalize_tree_frame(raw, depth:)
      return unless raw.is_a?(Hash)

      frame = parse_frame(raw, 0)
      return unless frame

      frame.merge(
        sample_count: positive_number(raw["sample_count"] || raw[:sample_count]),
        subframes: depth >= 64 ? [] : Array(raw["subframes"] || raw[:subframes]).first(100).filter_map { |child| normalize_tree_frame(child, depth: depth + 1) }
      )
    end

    def normalize_thread(raw, index)
      return unless raw.is_a?(Hash)

      frames = normalize_frames(raw["frames"] || raw[:frames] || raw["stacktrace"] || raw[:stacktrace])
      reporting = diagnostic_kind == "reported_error" && (scalar(raw, "role").blank? || scalar(raw, "role") == "reporting")
      triggered = reporting ? false : boolean_value(raw["triggered"] || raw[:triggered] || raw["crashed"] || raw[:crashed], default: false)
      {
        id: scalar(raw, "id") || scalar(raw, "number") || index.to_s,
        name: scalar(raw, "name") || "Thread #{index}",
        role: scalar(raw, "role") || (reporting ? "reporting" : (triggered ? "crashed" : "unknown")),
        triggered:,
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
      frame = {
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
      derived = @derived_frames_by_identity[frame_identity(frame)]
      return frame unless derived

      frame.merge(
        qualified_method: derived["qualified_method"].presence || frame[:qualified_method],
        symbol_identity: derived["symbol_identity"].presence || frame[:symbol_identity],
        method_name: derived["method_name"].presence || frame[:method_name],
        file: derived["file"].presence || frame[:file],
        line_number: derived["line_number"].to_i.positive? ? derived["line_number"].to_i : frame[:line_number],
        application_frame: derived.key?("application_frame") ? derived["application_frame"] : frame[:application_frame],
        symbolicated: derived["symbolicated"] == true
      )
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

    def frame_identity(frame)
      values = frame.respond_to?(:stringify_keys) ? frame.stringify_keys : {}
      uuid = values["image_uuid"].to_s.delete("{}").upcase.presence
      image = values["image"].to_s.presence
      address = values["address"].to_s.downcase.presence
      relative = values["relative_address"].to_s.downcase.presence
      [ uuid || image, address || relative ].compact.join("@").presence
    end

    def nested_value(parent, child)
      value = context[parent] || context[parent.to_sym]
      return unless value.is_a?(Hash)

      return value[child] if value.key?(child)
      value[child.to_sym] if value.key?(child.to_sym)
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
