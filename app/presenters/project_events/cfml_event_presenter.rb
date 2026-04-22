# frozen_string_literal: true

module ProjectEvents
  class CfmlEventPresenter
    include PayloadSupport

    def initialize(event = nil, exception_data = nil)
      @event = event
      @exception_data = exception_data
    end

    def frames
      tag_context = exception_hash["tagContext"] || exception_hash[:tagContext] ||
        exception_hash["tag_context"] || exception_hash[:tag_context]
      return parse_backtrace_frames(tag_context) if tag_context.present?

      parse_backtrace_frames(exception_hash["backtrace"] || exception_hash[:backtrace])
    end

    def summary(fallback_message = nil)
      {
        class_name: exception_hash["class"].presence ||
          exception_hash[:class].presence ||
          exception_hash["type"].presence ||
          exception_hash[:type].presence ||
          "ColdFusion Exception",
        message: exception_hash["message"].presence ||
          exception_hash[:message].presence ||
          fallback_message.to_s.lines.first.to_s.strip.presence ||
          "Unhandled CFML exception",
        detail: exception_hash["detail"].presence ||
          exception_hash[:detail].presence ||
          exception_hash["extendedInfo"].presence ||
          exception_hash[:extendedInfo].presence,
        error_code: exception_hash["errorCode"].presence || exception_hash[:errorCode].presence,
        extended_info: exception_hash["extendedInfo"].presence || exception_hash[:extendedInfo].presence
      }
    end

    def request_details
      cgi = normalize_hash(context["cgi"] || context[:cgi] || context["CGI"] || context[:CGI])
      generic_request = RequestContextPresenter.new(@event).details

      {
        script_name: value_from_hash(cgi, "script_name") || value_from_hash(cgi, "SCRIPT_NAME"),
        request_method: value_from_hash(cgi, "request_method") || value_from_hash(cgi, "REQUEST_METHOD") || generic_request[:http_method],
        query_string: value_from_hash(cgi, "query_string") || value_from_hash(cgi, "QUERY_STRING"),
        remote_addr: value_from_hash(cgi, "remote_addr") || value_from_hash(cgi, "REMOTE_ADDR") || generic_request[:client_ip],
        http_user_agent: value_from_hash(cgi, "http_user_agent") || value_from_hash(cgi, "HTTP_USER_AGENT"),
        url: generic_request[:url]
      }
    end

    private

    def context
      @context ||= event_context_hash(@event)
    end

    def exception_hash
      @exception_hash ||= normalize_hash(@exception_data)
    end
  end
end
