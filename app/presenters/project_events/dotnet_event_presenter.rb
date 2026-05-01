# frozen_string_literal: true

module ProjectEvents
  class DotnetEventPresenter
    include PayloadSupport

    def initialize(event = nil, exception_data = nil)
      @event = event
      @exception_data = exception_data
    end

    def stack
      value = exception_hash["stack"] || exception_hash[:stack] ||
        exception_hash["stack_trace"] || exception_hash[:stack_trace]
      return value.to_s if value.present?

      Array(exception_hash["backtrace"] || exception_hash[:backtrace]).join("\n")
    end

    def frames
      frame_payload = exception_hash["frames"] || exception_hash[:frames]
      return parse_backtrace_frames(frame_payload) if frame_payload.present?

      parse_backtrace_frames(stack.to_s.lines.map(&:strip).reject(&:blank?))
    end

    def summary(fallback_message = nil)
      {
        class_name: exception_hash["class"].presence ||
          exception_hash[:class].presence ||
          exception_hash["type"].presence ||
          exception_hash[:type].presence ||
          exception_hash["qualified_class"].presence ||
          exception_hash[:qualified_class].presence ||
          ".NET exception",
        message: exception_hash["message"].presence ||
          exception_hash[:message].presence ||
          fallback_message.to_s.lines.first.to_s.strip.presence ||
          "Unhandled .NET exception",
        hresult: exception_hash["hresult"].presence || exception_hash[:hresult].presence,
        source: exception_hash["source"].presence || exception_hash[:source].presence,
        target_site: exception_hash["target_site"].presence || exception_hash[:target_site].presence
      }
    end

    def exception_chain
      collect_exception_chain(exception_hash)
    end

    def runtime_details
      {
        framework: value_from_hash(context, "framework"),
        runtime: value_from_hash(context, "runtime"),
        dotnet_version: value_from_hash(context, "dotnet_version"),
        framework_description: value_from_hash(context, "framework_description"),
        os_description: value_from_hash(context, "os_description"),
        machine_name: value_from_hash(context, "machine_name"),
        process_id: value_from_hash(context, "process_id"),
        release: value_from_hash(context, "release"),
        environment: value_from_hash(context, "environment")
      }
    end

    def execution_details
      {
        route: value_from_hash(context, "route"),
        endpoint: value_from_hash(context, "endpoint"),
        status: value_from_hash(context, "status"),
        request_id: value_from_hash(context, "request_id"),
        trace_id: value_from_hash(context, "trace_id"),
        duration_ms: value_from_hash(context, "duration_ms")
      }
    end

    def logger_details
      logger = normalize_hash(context["logger"] || context[:logger])

      {
        logger_name: value_from_hash(context, "logger_name") || value_from_hash(logger, "name") || value_from_hash(logger, "category"),
        event_id: value_from_hash(logger, "event_id") || value_from_hash(logger, "eventId"),
        event_name: value_from_hash(logger, "event_name") || value_from_hash(logger, "eventName"),
        source_context: value_from_hash(logger, "source_context") || value_from_hash(logger, "sourceContext"),
        scope: value_from_hash(logger, "scope")
      }
    end

    def log_record_details
      normalize_hash(context["log_record"] || context[:log_record])
    end

    def exception_data
      normalize_hash(exception_hash["data"] || exception_hash[:data])
    end

    def developer_exception_title(fallback_message = nil, compact: false)
      current_summary = summary(fallback_message)
      message = current_summary[:message].to_s
      message = compact ? message.gsub(/\s+/, " ").strip : message.lines.first.to_s.strip

      [ current_summary[:class_name], message ].compact_blank.join(": ")
    end

    def endpoint_matches(fallback_message = nil)
      explicit_matches = first_present_value(context, "endpoint_matches", "candidate_endpoints", "matches")
      values = Array(explicit_matches).filter_map { |value| value.to_s.strip.presence }
      return values if values.any?

      message = summary(fallback_message)[:message].to_s
      match_text = message[/Matches:\s*(?<matches>.+)\z/m, :matches]
      match_text.to_s.lines.map(&:strip).compact_blank
    end

    def stack_lines
      lines = stack.to_s.lines.map(&:strip).compact_blank
      return lines if lines.any?

      frames.map { |frame| stack_line_for(frame) }.compact_blank
    end

    def query_parameters
      direct_query = normalize_hash(first_present_value(request_context, "query", "query_params", "queryParameters", "params"))
      return direct_query if direct_query.any?

      raw_query = first_present_value(request_context, "query_string", "queryString")
      raw_query ||= query_string_from_url(first_present_value(request_context, "url"))
      return {} if raw_query.blank?

      Rack::Utils.parse_nested_query(raw_query.to_s.delete_prefix("?"))
    rescue StandardError
      { "query_string" => raw_query.to_s }
    end

    def request_headers
      normalize_hash(first_present_value(request_context, "headers") || first_present_value(context, "headers"))
    end

    def request_cookies
      direct_cookies = normalize_hash(first_present_value(request_context, "cookies") || first_present_value(context, "cookies"))
      return direct_cookies if direct_cookies.any?

      cookie_header = value_from_hash(request_headers, "Cookie")
      return {} if cookie_header.blank?

      Rack::Utils.parse_cookies_header(cookie_header.to_s)
    rescue StandardError
      {}
    end

    def routing_details
      request_route = first_present_value(request_context, "route", "route_values", "routeValues")
      route_values = normalize_hash(request_route)
      route_label = request_route unless request_route.is_a?(Hash)

      {
        endpoint: first_present_value(context, "endpoint") || first_present_value(request_context, "endpoint"),
        route: first_present_value(context, "route") || route_label,
        route_values: route_values.presence,
        path: first_present_value(request_context, "path"),
        method: first_present_value(request_context, "method", "http_method", "httpMethod"),
        url: first_present_value(request_context, "url"),
        status: first_present_value(context, "status") || first_present_value(request_context, "status"),
        request_id: first_present_value(context, "request_id", "requestId") || first_present_value(request_context, "request_id", "requestId"),
        trace_id: first_present_value(context, "trace_id", "traceId") || first_present_value(request_context, "trace_id", "traceId"),
        duration_ms: first_present_value(context, "duration_ms", "durationMs")
      }.compact_blank
    end

    def activity_summary
      logger = logger_details
      execution = execution_details
      runtime = runtime_details

      parts = []
      parts << logger[:logger_name] if logger[:logger_name].present?
      parts << logger[:event_name] if logger[:event_name].present?
      parts << execution[:route] if execution[:route].present?
      parts << "status #{execution[:status]}" if execution[:status].present?
      parts << runtime[:framework] if runtime[:framework].present?
      parts.compact_blank.join(" · ").presence
    end

    private

    def context
      @context ||= event_context_hash(@event)
    end

    def request_context
      @request_context ||= normalize_hash(context["request"] || context[:request])
    end

    def exception_hash
      @exception_hash ||= normalize_hash(@exception_data)
    end

    def first_present_value(hash, *keys)
      keys.each do |key|
        value = value_from_hash(hash, key)
        return value if value.present?
      end

      nil
    end

    def query_string_from_url(url)
      value = url.to_s
      return nil unless value.include?("?")

      value.split("?", 2).last.to_s.split("#", 2).first.presence
    end

    def stack_line_for(frame)
      return nil unless frame.is_a?(Hash)

      raw = frame[:raw].to_s
      return raw if raw.present? && !raw.start_with?("{")

      method_name = frame[:method_name].presence
      file = frame[:file].presence
      line_number = frame[:line_number].presence

      if method_name.present? && file.present? && line_number.present?
        "at #{method_name} in #{file}:line #{line_number}"
      elsif method_name.present?
        "at #{method_name}"
      elsif file.present? && line_number.present?
        "at #{file}:line #{line_number}"
      elsif file.present?
        "at #{file}"
      end
    end

    def collect_exception_chain(hash, chain = [])
      current = normalize_hash(hash)
      return chain unless current.present?

      nested = normalize_hash(current["inner_exception"] || current[:inner_exception] || current["cause"] || current[:cause])
      if nested.present?
        chain << chain_entry("inner", nested)
        collect_exception_chain(nested, chain)
      end

      inner_exceptions = current["inner_exceptions"] || current[:inner_exceptions]
      if inner_exceptions.is_a?(Array)
        inner_exceptions.each do |entry|
          entry_hash = normalize_hash(entry)
          chain << chain_entry("aggregate", entry_hash) if entry_hash.present?
        end
      end

      chain
    end

    def chain_entry(label, hash)
      {
        label: label,
        class_name: hash["class"].presence || hash[:class].presence || hash["qualified_class"].presence || hash[:qualified_class].presence,
        message: hash["message"].presence || hash[:message].presence,
        frames: self.class.new(nil, hash).frames
      }
    end
  end
end
