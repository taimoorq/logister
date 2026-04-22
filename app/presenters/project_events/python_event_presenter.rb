# frozen_string_literal: true

module ProjectEvents
  class PythonEventPresenter
    include PayloadSupport

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
      {
        route: value_from_hash(context, "route"),
        endpoint: value_from_hash(context, "endpoint"),
        blueprint: value_from_hash(context, "blueprint"),
        task_name: value_from_hash(context, "task_name"),
        task_id: value_from_hash(context, "task_id"),
        task_module: value_from_hash(context, "task_module"),
        queue: value_from_hash(context, "queue"),
        retries: value_from_hash(context, "retries"),
        eta: value_from_hash(context, "eta"),
        client_ip: value_from_hash(context, "client_ip"),
        query_string: value_from_hash(context, "query_string")
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

    def exception_hash
      @exception_hash ||= normalize_hash(@exception_data)
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
