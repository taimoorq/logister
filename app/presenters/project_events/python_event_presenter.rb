# frozen_string_literal: true

module ProjectEvents
  class PythonEventPresenter
    include PayloadSupport

    KNOWN_CONTEXT_KEYS = %w[
      blueprint check_in_slug check_in_status client_ip duration_ms endpoint environment eta exception expected_interval_seconds
      framework headers hostname logger logger_name log_record method params path platform process_id python_implementation
      python_version query_string queue release request request_id retries route runtime runtime_name session_id status
      status_code task_args_count task_id task_kwargs_keys task_module task_name task_result task_state trace_id transaction_name
      url user_id
    ].freeze

    def initialize(event = nil, exception_data = nil)
      @event = event
      @exception_data = exception_data
    end

    def frames
      frame_payload = exception_hash["frames"] || exception_hash[:frames]
      return parse_backtrace_frames(frame_payload) if frame_payload.present?

      parse_backtrace_frames(exception_hash["backtrace"] || exception_hash[:backtrace])
    end

    def summary(fallback_message = nil)
      {
        class_name: exception_hash["class"].presence ||
          exception_hash[:class].presence ||
          exception_hash["type"].presence ||
          exception_hash[:type].presence ||
          exception_hash["qualified_class"].presence ||
          exception_hash[:qualified_class].presence ||
          "Python exception",
        message: exception_hash["message"].presence ||
          exception_hash[:message].presence ||
          fallback_message.to_s.lines.first.to_s.strip.presence ||
          "Unhandled Python exception"
      }
    end

    def exception_chain
      collect_exception_chain(exception_hash)
    end

    def runtime_details
      {
        framework: value_from_hash(context, "framework"),
        runtime: value_from_hash(context, "runtime"),
        python_version: value_from_hash(context, "python_version"),
        python_implementation: value_from_hash(context, "python_implementation"),
        platform: value_from_hash(context, "platform"),
        hostname: value_from_hash(context, "hostname"),
        process_id: value_from_hash(context, "process_id"),
        runtime_name: value_from_hash(context, "runtime_name"),
        release: value_from_hash(context, "release"),
        environment: value_from_hash(context, "environment")
      }
    end

    def execution_details
      request = request_context

      {
        method: first_present_value(request, "method", "http_method", "httpMethod") || value_from_hash(context, "method"),
        path: first_present_value(request, "path") || value_from_hash(context, "path"),
        url: first_present_value(request, "url") || value_from_hash(context, "url"),
        status_code: first_present_value(context, "status_code", "statusCode", "status") ||
          first_present_value(request, "status_code", "statusCode", "status"),
        route: value_from_hash(context, "route") || first_present_value(request, "route"),
        endpoint: value_from_hash(context, "endpoint") || first_present_value(request, "endpoint"),
        blueprint: value_from_hash(context, "blueprint") || first_present_value(request, "blueprint"),
        path_params: normalize_hash(first_present_value(request, "path_params", "pathParams")),
        view_args: normalize_hash(first_present_value(request, "view_args", "viewArgs")),
        headers: normalize_hash(first_present_value(request, "headers") || first_present_value(context, "headers")),
        task_name: value_from_hash(context, "task_name"),
        task_id: value_from_hash(context, "task_id"),
        task_module: value_from_hash(context, "task_module"),
        task_state: value_from_hash(context, "task_state"),
        task_args_count: value_from_hash(context, "task_args_count"),
        task_kwargs_keys: value_from_hash(context, "task_kwargs_keys"),
        task_result: value_from_hash(context, "task_result"),
        queue: value_from_hash(context, "queue"),
        retries: value_from_hash(context, "retries"),
        eta: value_from_hash(context, "eta"),
        client_ip: value_from_hash(context, "client_ip") || first_present_value(request, "client_ip", "clientIp"),
        query_string: value_from_hash(context, "query_string") || first_present_value(request, "query_string", "queryString"),
        request_id: value_from_hash(context, "request_id") || first_present_value(request, "request_id", "requestId"),
        trace_id: value_from_hash(context, "trace_id") || first_present_value(request, "trace_id", "traceId"),
        transaction_name: value_from_hash(context, "transaction_name"),
        duration_ms: value_from_hash(context, "duration_ms"),
        session_id: value_from_hash(context, "session_id"),
        user_id: value_from_hash(context, "user_id"),
        expected_interval_seconds: value_from_hash(context, "expected_interval_seconds"),
        check_in_slug: value_from_hash(context, "check_in_slug"),
        check_in_status: value_from_hash(context, "check_in_status")
      }
    end

    def logger_details
      logger = normalize_hash(context["logger"] || context[:logger])

      {
        logger_name: value_from_hash(context, "logger_name") || value_from_hash(logger, "name"),
        module: value_from_hash(logger, "module"),
        pathname: value_from_hash(logger, "pathname"),
        filename: value_from_hash(logger, "filename"),
        function: value_from_hash(logger, "function"),
        line_number: value_from_hash(logger, "line_number"),
        process: value_from_hash(logger, "process"),
        thread: value_from_hash(logger, "thread")
      }
    end

    def log_record_details
      normalize_hash(context["log_record"] || context[:log_record])
    end

    def traceback_text(fallback_message = nil)
      if frames.any?
        return python_traceback_from_frames(fallback_message)
      end

      raw_backtrace = Array(exception_hash["backtrace"] || exception_hash[:backtrace]).map(&:to_s).compact_blank
      return raw_backtrace.join("\n") if raw_backtrace.any?

      fallback_message.to_s.presence || summary(fallback_message).values.compact_blank.join(": ")
    end

    def custom_context_details
      context.each_with_object({}) do |(key, value), details|
        key_string = key.to_s
        next if KNOWN_CONTEXT_KEYS.include?(key_string)
        next if value.nil? || value == "" || value == {} || value == []

        details[key_string] = value
      end
    end

    def activity_summary
      logger = logger_details
      execution = execution_details

      parts = []
      parts << logger[:logger_name] if logger[:logger_name].present?

      origin = if logger[:function].present? && logger[:filename].present?
        "#{logger[:function]}() in #{logger[:filename]}"
      elsif logger[:function].present?
        "#{logger[:function]}()"
      elsif logger[:filename].present?
        logger[:filename]
      end
      parts << origin if origin.present?

      if execution[:task_name].present?
        parts << "task #{execution[:task_name]}"
      elsif execution[:route].present?
        parts << execution[:route]
      elsif execution[:endpoint].present?
        parts << execution[:endpoint]
      end

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

    def python_traceback_from_frames(fallback_message)
      current_summary = summary(fallback_message)
      lines = [ "Traceback (most recent call last):" ]

      frames.each do |frame|
        method_name = frame[:method_name].presence || "<module>"
        lines << %(  File "#{frame[:file]}", line #{frame[:line_number]}, in #{method_name})

        code_line = frame[:code_context].to_s.lines.first.to_s.strip
        lines << "    #{code_line}" if code_line.present?
      end

      lines << [ current_summary[:class_name], current_summary[:message] ].compact_blank.join(": ")
      lines.join("\n")
    end

    def collect_exception_chain(hash, chain = [], label: "cause")
      current = normalize_hash(hash)
      return chain unless current.present?

      cause = normalize_hash(current["cause"] || current[:cause])
      if cause.present?
        chain << {
          label: label,
          class_name: cause["class"].presence || cause[:class].presence || cause["qualified_class"].presence || cause[:qualified_class].presence,
          message: cause["message"].presence || cause[:message].presence,
          frames: self.class.new(nil, cause).frames
        }
        collect_exception_chain(cause, chain, label: "cause")
      end

      nested_context = normalize_hash(current["context"] || current[:context])
      if nested_context.present?
        chain << {
          label: "context",
          class_name: nested_context["class"].presence || nested_context[:class].presence || nested_context["qualified_class"].presence || nested_context[:qualified_class].presence,
          message: nested_context["message"].presence || nested_context[:message].presence,
          frames: self.class.new(nil, nested_context).frames
        }
        collect_exception_chain(nested_context, chain, label: "context")
      end

      chain
    end
  end
end
