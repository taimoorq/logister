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
    end

    def exception
      @exception
    end

    def exception_type
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

    def exception_data_policy
      nested_scalar("error", "data_policy") || scalar(@context, "exception_data_policy")
    end

    def exception_detail_redacted?
      %w[type_and_stacktrace metadata_only].include?(exception_data_policy)
    end

    def frames
      normalize_frames(exception["stacktrace"] || exception[:stacktrace] || exception["backtrace"] || exception[:backtrace])
    end

    def all_frames
      cause_chain.reverse.flat_map { |entry| entry[:frames] }
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
      frames.first
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
        session: nested_scalar("session", "id") || scalar(@context, "session_id"),
        installation: nested_scalar("installation", "id_hash") || scalar(@context, "installation_id_hash"),
        user: scalar(@context, "user_id"),
        trace: scalar(@context, "trace_id")
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

    def normalize_frames(value)
      Array(value).filter_map do |raw|
        if raw.is_a?(Hash)
          class_name = scalar(raw, "class") || scalar(raw, "class_name") || scalar(raw, "module")
          method_name = scalar(raw, "method") || scalar(raw, "method_name") || scalar(raw, "function")
          file = scalar(raw, "file") || scalar(raw, "filename") || class_name
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
