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

    def exception_hash
      @exception_hash ||= normalize_hash(@exception_data)
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
