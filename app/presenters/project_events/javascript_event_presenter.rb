# frozen_string_literal: true

module ProjectEvents
  class JavascriptEventPresenter
    include PayloadSupport

    def initialize(event = nil, exception_data = nil)
      @event = event
      @exception_data = exception_data
    end

    def stack
      value = exception_hash["stack"] || exception_hash[:stack]
      return value.to_s if value.present?

      Array(exception_hash["backtrace"] || exception_hash[:backtrace]).join("\n")
    end

    def frames
      frame_payload = exception_hash["frames"] || exception_hash[:frames]
      return parse_backtrace_frames(frame_payload) if frame_payload.present?

      lines = stack.to_s.lines.map(&:strip).reject(&:blank?)
      lines = lines.drop(1) if lines.first&.match?(/\A[\w$.]+(?::|Error)/)
      parse_backtrace_frames(lines)
    end

    def summary(fallback_message = nil)
      stack_lines = stack.to_s.lines.map(&:strip)
      headline = stack_lines.first.to_s
      inferred_class, inferred_message = if headline.include?(":")
        headline.split(":", 2).map(&:strip)
      end

      {
        class_name: exception_hash["class"].presence ||
          exception_hash[:class].presence ||
          exception_hash["name"].presence ||
          exception_hash[:name].presence ||
          inferred_class.presence ||
          "JavaScript Error",
        message: exception_hash["message"].presence ||
          exception_hash[:message].presence ||
          inferred_message.presence ||
          fallback_message.to_s.lines.first.to_s.strip.presence ||
          "Unhandled JavaScript exception"
      }
    end

    def exception_chain
      collect_exception_chain(exception_hash)
    end

    def runtime_details
      headers = normalize_hash(RequestContextPresenter.new(@event).details[:headers])

      {
        browser: value_from_hash(context, "browser"),
        os: value_from_hash(context, "os"),
        runtime: value_from_hash(context, "runtime"),
        release: value_from_hash(context, "release"),
        environment: value_from_hash(context, "environment"),
        route: value_from_hash(context, "route"),
        component: value_from_hash(context, "component"),
        user_agent: value_from_hash(context, "user_agent") ||
          value_from_hash(context, "userAgent") ||
          value_from_hash(headers, "User-Agent"),
        url: request_scalar_value(context, :url),
        request_id: request_scalar_value(context, :request_id)
      }
    end

    def logger_details
      logger = normalize_hash(context["logger"] || context[:logger])

      {
        logger_name: value_from_hash(context, "logger_name") || value_from_hash(logger, "name"),
        method: value_from_hash(logger, "method"),
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
      runtime = runtime_details

      parts = []
      parts << logger[:logger_name] if logger[:logger_name].present?
      parts << logger[:method] if logger[:method].present?

      origin = if logger[:function].present? && logger[:filename].present?
        "#{logger[:function]}() in #{logger[:filename]}"
      elsif logger[:function].present?
        "#{logger[:function]}()"
      elsif logger[:filename].present?
        logger[:filename]
      end
      parts << origin if origin.present?
      parts << runtime[:route] if runtime[:route].present?
      parts << runtime[:component] if runtime[:component].present?

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
          class_name: cause["class"].presence || cause[:class].presence || cause["name"].presence || cause[:name].presence,
          message: cause["message"].presence || cause[:message].presence,
          frames: self.class.new(nil, cause).frames
        }
        collect_exception_chain(cause, chain, label: "cause")
      end

      nested_context = normalize_hash(current["context"] || current[:context])
      if nested_context.present?
        nested_values = nested_context["values"] || nested_context[:values]
        if nested_values.is_a?(Array)
          nested_values.each do |entry|
            next unless entry.is_a?(Hash)

            chain << {
              label: "context",
              class_name: entry["class"].presence || entry[:class].presence || "JavaScript Error",
              message: entry["message"].presence || entry[:message].presence,
              frames: self.class.new(nil, entry).frames
            }
          end
        else
          chain << {
            label: "context",
            class_name: nested_context["class"].presence || nested_context[:class].presence,
            message: nested_context["message"].presence || nested_context[:message].presence,
            frames: self.class.new(nil, nested_context).frames
          }
        end
      end

      chain.compact_blank
    end
  end
end
