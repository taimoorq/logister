# frozen_string_literal: true

module ProjectEvents
  class AndroidEventPresenter
    include PayloadSupport

    MECHANISM_LABELS = {
      "handled_exception" => "Reported exception",
      "unhandled_exception" => "Fatal",
      "anr" => "ANR",
      "native_crash" => "Native crash",
      "low_memory_kill" => "Low-memory exit",
      "unknown" => "Reported exception"
    }.freeze

    CAPTURE_SOURCE_LABELS = {
      "automatic" => "Automatic capture",
      "manual" => "Reported by app",
      "historical_exit" => "Recovered after restart"
    }.freeze

    attr_reader :event

    def initialize(event, exception_data = nil)
      @event = event
      @context = event_context_hash(event)
      @exception = normalize_hash(exception_data.presence || @context["exception"] || @context[:exception])
      @diagnostic = normalize_hash(@context["diagnostic"] || @context[:diagnostic])
    end

    def exception
      @exception
    end

    def exception_type
      return failure_type_label if exception.blank? && historical_exit?

      scalar(exception, "type") || scalar(exception, "class") || "Unknown exception"
    end

    def exception_message
      scalar(exception, "message") || event&.message.to_s.presence
    end

    def mechanism
      value = nested_scalar("error", "mechanism") || scalar(@context, "error_mechanism")
      value ||= "handled_exception" if exception.present?
      value ||= "unknown"
      MECHANISM_LABELS.key?(value) ? value : "unknown"
    end

    def mechanism_label
      MECHANISM_LABELS.fetch(mechanism)
    end

    def failure_type_label
      mechanism_label
    end

    def technical_signature
      if exception.blank? && capture_source == "historical_exit"
        method = top_in_app_frame&.dig(:qualified_method).presence || top_in_app_frame&.dig(:method_name).presence
        return [ mechanism_label, method ].compact_blank.join(" · ") if method.present?

        reason = scalar(@context, "application_exit_description") || scalar(@context, "application_exit_reason")
        return [ mechanism_label, reason ].compact_blank.join(" · ")
      end

      cause = root_cause || {}
      type = cause[:type].presence || exception_type.presence
      method = top_in_app_frame&.dig(:qualified_method).presence || top_in_app_frame&.dig(:method_name).presence
      [ type, method.present? && "in #{method}" ].compact_blank.join(" ").presence || event&.message.to_s.presence
    end

    def culprit_location
      frame = top_in_app_frame
      return if frame.blank?

      location = frame[:file].presence
      location = "#{location}:#{frame[:line_number]}" if location && frame[:line_number]
      location
    end

    def historical_exit?
      capture_source == "historical_exit"
    end

    def stack_not_applicable?
      historical_exit? && all_frames.empty?
    end

    def application_exit_details
      compact_details(
        reason: scalar(@context, "application_exit_reason"),
        description: scalar(@context, "application_exit_description"),
        status: scalar(@context, "application_exit_status"),
        importance: scalar(@context, "application_exit_importance"),
        process: nested_scalar("app", "process") || scalar(@context, "process_name"),
        last_pss: measurement_label("last_pss"),
        last_rss: measurement_label("last_rss")
      )
    end

    def measurement_summary
      [ measurement_label("last_pss", prefix: "Last PSS"), measurement_label("last_rss", prefix: "Last RSS") ].compact_blank.join(" · ").presence
    end

    def handled?
      value = nested_value("error", "handled")
      value = @context["handled"] if value.nil?
      value = true if value.nil? && exception.present? && mechanism == "handled_exception"
      value == true || value.to_s == "true"
    end

    def user_perceived?
      value = nested_value("error", "user_perceived")
      value == true || value.to_s == "true"
    end

    def capture_source
      nested_scalar("error", "capture_source") || scalar(@context, "capture_source")
    end

    def capture_source_label
      CAPTURE_SOURCE_LABELS[capture_source]
    end

    def error_thread_name
      nested_scalar("error", "thread_name") || scalar(@context, "error_thread_name")
    end

    def exception_data_policy
      nested_scalar("error", "data_policy") || scalar(@context, "exception_data_policy")
    end

    def exception_detail_redacted?
      return false if exception.blank?

      %w[type_and_stacktrace metadata_only].include?(exception_data_policy)
    end

    def frames
      exception_frames = normalize_frames(exception["stacktrace"] || exception[:stacktrace] || exception["backtrace"] || exception[:backtrace])
      return exception_frames if exception_frames.any?

      sampled_threads.find { |thread| thread[:attributed] }&.dig(:frames) || sampled_threads.first&.dig(:frames) || []
    end

    def all_frames
      return sampled_threads.flat_map { |thread| thread[:frames] } if exception.blank? && sampled_threads.any?

      cause_chain.reverse.flat_map { |entry| entry[:frames] }
    end

    def sampled_threads
      @sampled_threads ||= begin
        dump = normalize_hash(@diagnostic["thread_dump"] || @diagnostic[:thread_dump])
        Array(dump["threads"] || dump[:threads]).filter_map do |raw|
          next unless raw.is_a?(Hash)

          thread = normalize_hash(raw)
          frames = normalize_frames(thread["frames"] || thread[:frames])
          next if frames.empty?

          {
            name: scalar(thread, "name") || "sampled thread",
            role: scalar(thread, "role") || "sampled",
            attributed: truthy?(thread["attributed"] || thread[:attributed]),
            frames: frames
          }
        end.sort_by { |thread| thread[:attributed] ? 0 : 1 }
      end
    end

    def historical_thread_dump?
      historical_exit? && sampled_threads.any?
    end

    def thread_dump_truncated?
      dump = normalize_hash(@diagnostic["thread_dump"] || @diagnostic[:thread_dump])
      truthy?(dump["truncated"] || dump[:truncated])
    end

    def cause_chain
      entries = []
      current = exception
      depth = 0

      while current.is_a?(Hash) && current.present? && depth < 12
        entries << {
          depth: depth,
          type: scalar(current, "type") || scalar(current, "class") || "Unknown exception",
          message: scalar(current, "message"),
          frames: normalize_frames(current["stacktrace"] || current[:stacktrace] || current["backtrace"] || current[:backtrace])
        }
        current = normalize_hash(current["cause"] || current[:cause])
        depth += 1
      end

      entries
    end

    def root_cause
      cause_chain.last
    end

    def top_in_app_frame
      cause_chain.reverse_each do |entry|
        frame = entry[:frames].find { |candidate| candidate[:application_frame] }
        return frame if frame
      end
      all_frames.find { |candidate| candidate[:application_frame] } || frames.first
    end

    def package_name
      nested_scalar("app", "package_name") || scalar(@context, "package_name") || scalar(@context, "service")
    end

    def app_details
      compact_details(
        package_name: package_name,
        version_name: nested_scalar("app", "version_name") || scalar(@context, "app_version"),
        version_code: nested_scalar("app", "version_code") || scalar(@context, "build_number"),
        build_type: nested_scalar("app", "build_type") || scalar(@context, "build_type"),
        release: scalar(@context, "release"),
        track: nested_scalar("distribution", "track") || scalar(@context, "distribution_track"),
        process: nested_scalar("app", "process") || scalar(@context, "process_name"),
        screen: nested_scalar("app", "screen") || scalar(@context, "screen_name"),
        in_foreground: nested_value("app", "in_foreground")
      )
    end

    def device_details
      compact_details(
        manufacturer: nested_scalar("device", "manufacturer") || scalar(@context, "device_manufacturer"),
        brand: nested_scalar("device", "brand") || scalar(@context, "device_brand"),
        model: nested_scalar("device", "model") || scalar(@context, "device_model"),
        form_factor: nested_scalar("device", "form_factor") || scalar(@context, "device_form_factor"),
        locale: nested_scalar("device", "locale") || scalar(@context, "locale")
      )
    end

    def os_details
      compact_details(
        name: nested_scalar("os", "name") || scalar(@context, "os_name") || "Android",
        version: nested_scalar("os", "version") || scalar(@context, "os_version"),
        api_level: nested_scalar("os", "api_level") || scalar(@context, "android_api_level")
      )
    end

    def correlation_details
      compact_details(
        session: masked_identifier(nested_scalar("session", "id") || scalar(@context, "session_id")),
        installation: masked_identifier(nested_scalar("installation", "id_hash") || scalar(@context, "installation_id_hash")),
        user: masked_identifier(scalar(@context, "user_id")),
        trace: masked_identifier(scalar(@context, "trace_id"))
      )
    end

    def breadcrumbs
      value = @context["breadcrumbs"] || @context[:breadcrumbs]
      Array(value).filter_map do |item|
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
      scalar(@context, "telemetry_schema_version")&.to_i
    end

    private

    def measurement_label(key, prefix: nil)
      measurements = normalize_hash(@diagnostic["measurements"] || @diagnostic[:measurements])
      measurement = normalize_hash(measurements[key] || measurements[key.to_sym])
      value = Float(measurement["value"] || measurement[:value], exception: false)
      unit = scalar(measurement, "unit")
      return unless value&.finite? && value >= 0 && unit == "bytes"

      label = format_bytes(value)
      prefix.present? ? "#{prefix} #{label}" : label
    end

    def format_bytes(value)
      units = %w[B KB MB GB TB]
      amount = value.to_f
      index = 0
      while amount >= 1024 && index < units.length - 1
        amount /= 1024
        index += 1
      end
      precision = amount >= 10 || amount == amount.round ? 0 : 1
      "#{amount.round(precision)} #{units[index]}"
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end

    def normalize_frames(value)
      Array(value).filter_map do |raw|
        if raw.is_a?(Hash)
          class_name = scalar(raw, "class") || scalar(raw, "class_name") || scalar(raw, "module")
          method_name = scalar(raw, "method") || scalar(raw, "method_name") || scalar(raw, "function")
          file = scalar(raw, "file") || scalar(raw, "file_name") || scalar(raw, "filename") || class_name
          line = scalar(raw, "line") || scalar(raw, "line_number") || scalar(raw, "lineno")
          next if class_name.blank? && method_name.blank? && file.blank?

          {
            raw: raw,
            class_name: class_name,
            qualified_method: [ class_name, method_name ].compact_blank.join("."),
            method_name: method_name,
            file: file,
            line_number: line.to_i.positive? ? line.to_i : nil,
            column_number: nil,
            code_context: nil,
            locals: {},
            absolute_path: nil,
            application_frame: in_app_frame?(class_name, raw)
          }
        else
          parse_java_line(raw.to_s)
        end
      end
    end

    def parse_java_line(line)
      match = /\A\s*at\s+(?<method>[^\s(]+)\((?<file>[^:()]+)(?::(?<line>\d+))?\)\s*\z/.match(line)
      return unless match

      qualified_method = match[:method]
      class_name = qualified_method.rpartition(".").first
      {
        raw: line,
        class_name: class_name,
        qualified_method: qualified_method,
        method_name: qualified_method.rpartition(".").last,
        file: match[:file],
        line_number: match[:line].to_i.positive? ? match[:line].to_i : nil,
        column_number: nil,
        code_context: nil,
        locals: {},
        absolute_path: nil,
        application_frame: in_app_frame?(class_name, {})
      }
    end

    def in_app_frame?(class_name, raw)
      explicit = raw["in_app"] || raw[:in_app]
      return explicit == true || explicit.to_s == "true" unless explicit.nil?

      prefix = package_name.to_s
      prefix.present? && class_name.to_s.start_with?(prefix)
    end

    def nested_value(parent, child)
      value = @context[parent] || @context[parent.to_sym]
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

    def compact_details(values)
      values.reject { |_key, value| value.nil? || (value.respond_to?(:blank?) && value.blank?) }
    end
  end
end
