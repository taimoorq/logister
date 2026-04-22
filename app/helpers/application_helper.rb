module ApplicationHelper
  DOCS_BASE_URL = ENV.fetch("LOGISTER_DOCS_URL", "https://docs.logister.org").chomp("/").freeze
  DOCS_PATHS = {
    overview: "/",
    getting_started: "/getting-started/",
    self_hosting: "/self-hosting/",
    local_development: "/local-development/",
    deployment: "/deployment/",
    clickhouse: "/clickhouse/",
    http_api: "/http-api/",
    ruby_integration: "/integrations/ruby/",
    cfml_integration: "/integrations/cfml/",
    javascript_integration: "/integrations/javascript/",
    python_integration: "/integrations/python/"
  }.freeze

  ICON_PATHS = {
    plus: "M12 2.75a.75.75 0 0 1 .75.75v7.75h7.75a.75.75 0 0 1 0 1.5h-7.75v7.75a.75.75 0 0 1-1.5 0v-7.75H3.5a.75.75 0 0 1 0-1.5h7.75V3.5a.75.75 0 0 1 .75-.75Z",
    dashboard: "M3 13.5a1.5 1.5 0 0 1 1.5-1.5H9a1.5 1.5 0 0 1 1.5 1.5V19A1.5 1.5 0 0 1 9 20.5H4.5A1.5 1.5 0 0 1 3 19v-5.5Zm10.5-8A1.5 1.5 0 0 1 15 4h4.5A1.5 1.5 0 0 1 21 5.5V11a1.5 1.5 0 0 1-1.5 1.5H15a1.5 1.5 0 0 1-1.5-1.5V5.5ZM3 5.5A1.5 1.5 0 0 1 4.5 4H9a1.5 1.5 0 0 1 1.5 1.5V8A1.5 1.5 0 0 1 9 9.5H4.5A1.5 1.5 0 0 1 3 8V5.5Zm10.5 8A1.5 1.5 0 0 1 15 12h4.5a1.5 1.5 0 0 1 1.5 1.5V19a1.5 1.5 0 0 1-1.5 1.5H15a1.5 1.5 0 0 1-1.5-1.5v-5.5Z",
    projects: "M3 7.5A2.5 2.5 0 0 1 5.5 5h4A2.5 2.5 0 0 1 12 7.5v1A2.5 2.5 0 0 1 9.5 11h-4A2.5 2.5 0 0 1 3 8.5v-1Zm9 8A2.5 2.5 0 0 1 14.5 13h4a2.5 2.5 0 0 1 2.5 2.5v1a2.5 2.5 0 0 1-2.5 2.5h-4a2.5 2.5 0 0 1-2.5-2.5v-1Zm-9 0A2.5 2.5 0 0 1 5.5 13h4A2.5 2.5 0 0 1 12 15.5v1A2.5 2.5 0 0 1 9.5 19h-4A2.5 2.5 0 0 1 3 16.5v-1ZM12 7.5A2.5 2.5 0 0 1 14.5 5h4A2.5 2.5 0 0 1 21 7.5v1a2.5 2.5 0 0 1-2.5 2.5h-4A2.5 2.5 0 0 1 12 8.5v-1Z",
    search: "M10.25 3.75a6.5 6.5 0 1 0 4.03 11.6l3.18 3.18a.75.75 0 1 0 1.06-1.06l-3.18-3.18a6.5 6.5 0 0 0-5.09-10.54Zm-5 6.5a5 5 0 1 1 10 0 5 5 0 0 1-10 0Z",
    account: "M12 12a4.25 4.25 0 1 0 0-8.5 4.25 4.25 0 0 0 0 8.5ZM4.5 19.25a7.5 7.5 0 1 1 15 0 .75.75 0 0 1-.75.75H5.25a.75.75 0 0 1-.75-.75Z",
    lock: "M12 2.75 4.5 5.9v5.35c0 4.7 3.11 8.98 7.5 10 4.39-1.02 7.5-5.3 7.5-10V5.9L12 2.75Zm0 5.25a2.5 2.5 0 0 1 2.5 2.5V12h.25A1.25 1.25 0 0 1 16 13.25v3.5A1.25 1.25 0 0 1 14.75 18h-5.5A1.25 1.25 0 0 1 8 16.75v-3.5A1.25 1.25 0 0 1 9.25 12h.25v-1.5A2.5 2.5 0 0 1 12 8Z",
    settings: "M12 2.75a.75.75 0 0 1 .75.75v1.027a7.75 7.75 0 0 1 3.521 1.46l.726-.726a.75.75 0 1 1 1.061 1.06l-.726.727a7.75 7.75 0 0 1 1.46 3.522H19.5a.75.75 0 0 1 0 1.5h-1.028a7.75 7.75 0 0 1-1.46 3.521l.727.726a.75.75 0 1 1-1.06 1.061l-.727-.726a7.75 7.75 0 0 1-3.522 1.46V20.5a.75.75 0 0 1-1.5 0v-1.028a7.75 7.75 0 0 1-3.521-1.46l-.726.727a.75.75 0 1 1-1.061-1.06l.726-.727a7.75 7.75 0 0 1-1.46-3.522H4.5a.75.75 0 0 1 0-1.5h1.027a7.75 7.75 0 0 1 1.46-3.521l-.726-.726a.75.75 0 1 1 1.06-1.061l.727.726a7.75 7.75 0 0 1 3.522-1.46V3.5a.75.75 0 0 1 .75-.75Z",
    external: "M13.5 4a.75.75 0 0 1 .75-.75h5.25a.75.75 0 0 1 .75.75v5.25a.75.75 0 0 1-1.5 0V5.81l-7.47 7.47a.75.75 0 0 1-1.06-1.06l7.47-7.47h-3.44A.75.75 0 0 1 13.5 4ZM4.75 6.75A2.75 2.75 0 0 1 7.5 4h3a.75.75 0 0 1 0 1.5h-3a1.25 1.25 0 0 0-1.25 1.25v9.75c0 .69.56 1.25 1.25 1.25h9.75c.69 0 1.25-.56 1.25-1.25v-3a.75.75 0 0 1 1.5 0v3A2.75 2.75 0 0 1 17.25 19H7.5a2.75 2.75 0 0 1-2.75-2.75V6.75Z",
    users: "M14.5 13a3 3 0 1 0-2.98-3.35A3.75 3.75 0 1 0 6 13.5 3.5 3.5 0 0 0 2.5 17v.25c0 .97.78 1.75 1.75 1.75h10.5c.97 0 1.75-.78 1.75-1.75V17a3.5 3.5 0 0 0-2-3.17Z",
    filter: "M3 5.75A.75.75 0 0 1 3.75 5h16.5a.75.75 0 0 1 .53 1.28l-6.03 6.03v5.94a.75.75 0 0 1-1.17.62l-3-2a.75.75 0 0 1-.33-.62v-3.94L3.22 6.28A.75.75 0 0 1 3 5.75Z",
    chart: "M4.75 19A1.75 1.75 0 0 1 3 17.25V6.75a.75.75 0 0 1 1.5 0v10.5c0 .14.11.25.25.25h14.5a.75.75 0 0 1 0 1.5H4.75Zm3-4a.75.75 0 0 1-.53-1.28l2.5-2.5a.75.75 0 0 1 1.06 0l1.47 1.47 3.97-3.97a.75.75 0 1 1 1.06 1.06l-4.5 4.5a.75.75 0 0 1-1.06 0l-1.47-1.47-1.97 1.97a.75.75 0 0 1-.53.22Z",
    calendar: "M7.75 2.75a.75.75 0 0 1 .75.75v1h7v-1a.75.75 0 0 1 1.5 0v1h.25A2.75 2.75 0 0 1 20 7.25v9A2.75 2.75 0 0 1 17.25 19H6.75A2.75 2.75 0 0 1 4 16.25v-9A2.75 2.75 0 0 1 6.75 4.5H7v-1a.75.75 0 0 1 .75-.75Zm10.75 6H5.5v7.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-7.5Z",
    check: "M9.55 16.28 5.97 12.7a.75.75 0 1 0-1.06 1.06l4.11 4.11a.75.75 0 0 0 1.06 0l9-9a.75.75 0 1 0-1.06-1.06l-8.47 8.47Z",
    warning: "M10.3 3.4a2 2 0 0 1 3.4 0l7.18 12.56A2 2 0 0 1 19.18 19H4.82a2 2 0 0 1-1.7-3.04L10.3 3.4ZM12 8.25a.75.75 0 0 0-.75.75v4.25a.75.75 0 0 0 1.5 0V9a.75.75 0 0 0-.75-.75Zm0 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z",
    archive: "M4.75 4h14.5A1.75 1.75 0 0 1 21 5.75v2.5A1.75 1.75 0 0 1 19.25 10H19v7.25A1.75 1.75 0 0 1 17.25 19H6.75A1.75 1.75 0 0 1 5 17.25V10h-.25A1.75 1.75 0 0 1 3 8.25v-2.5A1.75 1.75 0 0 1 4.75 4Zm2.5 8a.75.75 0 0 0 0 1.5h9.5a.75.75 0 0 0 0-1.5h-9.5Z",
    all: "M5.75 4A1.75 1.75 0 0 0 4 5.75v12.5C4 19.216 4.784 20 5.75 20h12.5A1.75 1.75 0 0 0 20 18.25V5.75A1.75 1.75 0 0 0 18.25 4H5.75Zm2 4.25a.75.75 0 0 1 .75-.75h7a.75.75 0 0 1 0 1.5h-7a.75.75 0 0 1-.75-.75Zm0 3.75a.75.75 0 0 1 .75-.75h7a.75.75 0 0 1 0 1.5h-7a.75.75 0 0 1-.75-.75Zm0 3.75a.75.75 0 0 1 .75-.75h4a.75.75 0 0 1 0 1.5h-4a.75.75 0 0 1-.75-.75Z",
    folder_open: "M3.75 6.5A2.5 2.5 0 0 1 6.25 4h3.06c.53 0 1.04.21 1.42.59l.82.82c.1.1.24.16.38.16h5.82a2.5 2.5 0 0 1 2.44 3.04l-1.44 6.5a2.5 2.5 0 0 1-2.44 1.96H5.62a2.5 2.5 0 0 1-2.44-3.04l1.44-6.5A2.5 2.5 0 0 1 7.06 5.57h2.03l-.46-.46a.5.5 0 0 0-.35-.15H6.25A1 1 0 0 0 5.25 6v.5a.75.75 0 0 1-1.5 0V6.5Z",
    pencil: "M15.58 3.22a2.25 2.25 0 0 1 3.18 3.18l-8.42 8.42a1.75 1.75 0 0 1-.74.44l-3.06.92a.75.75 0 0 1-.93-.93l.92-3.06c.09-.3.24-.56.44-.74l8.42-8.42ZM4.75 18.5a.75.75 0 0 0 0 1.5h14.5a.75.75 0 0 0 0-1.5H4.75Z",
    x: "M6.22 6.22a.75.75 0 1 1 1.06-1.06L12 9.94l4.72-4.72a.75.75 0 1 1 1.06 1.06L13.06 11l4.72 4.72a.75.75 0 1 1-1.06 1.06L12 12.06l-4.72 4.72a.75.75 0 1 1-1.06-1.06L10.94 11 6.22 6.28Z",
    arrow_left: "M10.78 5.22a.75.75 0 0 1 0 1.06L6.06 11h13.19a.75.75 0 0 1 0 1.5H6.06l4.72 4.72a.75.75 0 0 1-1.06 1.06l-6-6a.75.75 0 0 1 0-1.06l6-6a.75.75 0 0 1 1.06 0Z",
    upload: "M12 3.75a.75.75 0 0 1 .75.75v8.69l2.72-2.72a.75.75 0 1 1 1.06 1.06l-4 4a.75.75 0 0 1-1.06 0l-4-4a.75.75 0 1 1 1.06-1.06l2.72 2.72V4.5A.75.75 0 0 1 12 3.75ZM4.75 17a.75.75 0 0 1 .75.75v.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-.5a.75.75 0 0 1 1.5 0v.5A2.75 2.75 0 0 1 17.25 21H6.75A2.75 2.75 0 0 1 4 18.25v-.5A.75.75 0 0 1 4.75 17Z",
    clipboard: "M9.5 3.75A1.75 1.75 0 0 1 11.25 2h1.5A1.75 1.75 0 0 1 14.5 3.75H16A2.75 2.75 0 0 1 18.75 6.5v11A2.75 2.75 0 0 1 16 20.25H8A2.75 2.75 0 0 1 5.25 17.5v-11A2.75 2.75 0 0 1 8 3.75h1.5Zm1.75-.25a.25.25 0 0 0-.25.25v.5c0 .14.11.25.25.25h1.5a.25.25 0 0 0 .25-.25v-.5a.25.25 0 0 0-.25-.25h-1.5ZM8 5.25a1.25 1.25 0 0 0-1.25 1.25v11c0 .69.56 1.25 1.25 1.25h8c.69 0 1.25-.56 1.25-1.25v-11c0-.69-.56-1.25-1.25-1.25h-1.5v.25A1.75 1.75 0 0 1 12.75 7h-1.5A1.75 1.75 0 0 1 9.5 5.5v-.25H8Z",
    mail: "M4.75 4h14.5A1.75 1.75 0 0 1 21 5.75v12.5A1.75 1.75 0 0 1 19.25 20H4.75A1.75 1.75 0 0 1 3 18.25V5.75A1.75 1.75 0 0 1 4.75 4Zm-.25 2.31v11.94c0 .14.11.25.25.25h14.5a.25.25 0 0 0 .25-.25V6.31l-6.94 5.55a.9.9 0 0 1-1.12 0L4.5 6.31Zm1.6-.81L12 10.25l5.9-4.75H6.1Z",
    info: "M12 3.25a8.75 8.75 0 1 0 0 17.5 8.75 8.75 0 0 0 0-17.5Zm0 3.5a1 1 0 1 1 0 2 1 1 0 0 1 0-2Zm-.75 4a.75.75 0 0 1 1.5 0v5a.75.75 0 0 1-1.5 0v-5Z",
    key: "M14.5 3a6.5 6.5 0 0 0-6.37 7.79l-4.91 4.9a1.25 1.25 0 0 0 0 1.77l2.32 2.32a1.25 1.25 0 0 0 1.77 0l.74-.74a.75.75 0 0 0 .22-.53v-1h1a.75.75 0 0 0 .53-.22l.83-.84h1.12a.75.75 0 0 0 .53-.22l1.44-1.44A6.5 6.5 0 1 0 14.5 3Zm0 1.5a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm1.75 2.75a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z",
    shield: "M12 2.75 4.5 5.6v5.43c0 4.7 3.08 8.88 7.5 10.22 4.42-1.34 7.5-5.52 7.5-10.22V5.6L12 2.75Zm0 2 6 2.28v4c0 3.9-2.44 7.4-6 8.67-3.56-1.27-6-4.77-6-8.67v-4l6-2.28Z"
  }.freeze

  REQUEST_DETAIL_KEYS = {
    client_ip: [ [ "clientIp" ], [ "client_ip" ], [ "request", "clientIp" ], [ "request", "client_ip" ], [ "request", "ip" ], [ "request", "remote_ip" ] ],
    headers: [ [ "headers" ], [ "request", "headers" ] ],
    http_method: [ [ "httpMethod" ], [ "http_method" ], [ "method" ], [ "request", "httpMethod" ], [ "request", "http_method" ], [ "request", "method" ] ],
    http_version: [ [ "httpVersion" ], [ "http_version" ], [ "request", "httpVersion" ], [ "request", "http_version" ], [ "request", "version" ] ],
    params: [ [ "params" ], [ "request", "params" ] ],
    rails_action: [ [ "railsAction" ], [ "rails_action" ], [ "request", "railsAction" ], [ "request", "rails_action" ] ],
    referer: [ [ "referer" ], [ "referrer" ], [ "request", "referer" ], [ "request", "referrer" ] ],
    request_id: [ [ "requestId" ], [ "request_id" ], [ "request", "requestId" ], [ "request", "request_id" ], [ "request", "id" ] ],
    url: [ [ "url" ], [ "request", "url" ], [ "request", "original_url" ] ]
  }.freeze

  def request_context_details(event)
    context = event_context_hash(event)

    headers = normalize_hash(first_hash_value(context, :headers))
    params = normalize_hash(first_hash_value(context, :params))

    rails_action = first_scalar_value(context, :rails_action)
    if rails_action.blank?
      controller_name = value_from_hash(params, "controller")
      action_name = value_from_hash(params, "action")
      rails_action = "#{controller_name}##{action_name}" if controller_name.present? && action_name.present?
    end

    referer = first_scalar_value(context, :referer)
    referer ||= value_from_hash(headers, "Referer")
    referer ||= value_from_hash(headers, "Referrer")

    http_version = first_scalar_value(context, :http_version)
    http_version ||= value_from_hash(headers, "Version")

    {
      client_ip: first_scalar_value(context, :client_ip),
      headers: headers,
      http_method: first_scalar_value(context, :http_method),
      http_version: http_version,
      params: params,
      rails_action: rails_action,
      referer: referer,
      request_id: first_scalar_value(context, :request_id),
      url: first_scalar_value(context, :url)
    }
  end

  def pretty_context_json(value)
    JSON.pretty_generate(value)
  rescue StandardError
    value.to_s
  end

  # Parses Ruby-style backtrace lines into frame hashes usable by the debugger-like UI.
  def parse_backtrace_frames(backtrace)
    Array(backtrace).filter_map do |line|
      parsed = if line.is_a?(Hash)
        parse_structured_backtrace_frame(line)
      else
        parse_backtrace_line(line.to_s)
      end
      next if parsed.blank?

      absolute_path = absolute_source_path(parsed[:file])
      app_frame = application_frame_path?(parsed[:file], absolute_path)

      {
        raw: line.to_s,
        file: parsed[:file],
        line_number: parsed[:line_number],
        column_number: parsed[:column_number],
        method_name: parsed[:method_name],
        code_context: parsed[:code_context],
        locals: parsed[:locals],
        absolute_path: absolute_path,
        application_frame: app_frame
      }
    end
  end

  def cfml_exception_frames(exception_data)
    exception_hash = normalize_hash(exception_data)
    tag_context = exception_hash["tagContext"] || exception_hash[:tagContext] ||
      exception_hash["tag_context"] || exception_hash[:tag_context]
    return parse_backtrace_frames(tag_context) if tag_context.present?

    backtrace = exception_hash["backtrace"] || exception_hash[:backtrace]
    parse_backtrace_frames(backtrace)
  end

  def cfml_exception_summary(exception_data, fallback_message = nil)
    exception_hash = normalize_hash(exception_data)

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

  def python_exception_frames(exception_data)
    exception_hash = normalize_hash(exception_data)
    frames = exception_hash["frames"] || exception_hash[:frames]
    return parse_backtrace_frames(frames) if frames.present?

    backtrace = exception_hash["backtrace"] || exception_hash[:backtrace]
    parse_backtrace_frames(backtrace)
  end

  def python_exception_summary(exception_data, fallback_message = nil)
    exception_hash = normalize_hash(exception_data)

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

  def python_exception_chain(exception_data, chain = [], label: "cause")
    exception_hash = normalize_hash(exception_data)
    return chain unless exception_hash.present?

    cause = normalize_hash(exception_hash["cause"] || exception_hash[:cause])
    if cause.present?
      chain << {
        label: label,
        class_name: cause["class"].presence || cause[:class].presence || cause["qualified_class"].presence || cause[:qualified_class].presence,
        message: cause["message"].presence || cause[:message].presence,
        frames: python_exception_frames(cause)
      }
      python_exception_chain(cause, chain, label: "cause")
    end

    context = normalize_hash(exception_hash["context"] || exception_hash[:context])
    if context.present?
      chain << {
        label: "context",
        class_name: context["class"].presence || context[:class].presence || context["qualified_class"].presence || context[:qualified_class].presence,
        message: context["message"].presence || context[:message].presence,
        frames: python_exception_frames(context)
      }
      python_exception_chain(context, chain, label: "context")
    end

    chain
  end

  def python_runtime_details(event)
    context = event_context_hash(event)

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

  def python_execution_details(event)
    context = event_context_hash(event)

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

  def python_logger_details(event)
    context = event_context_hash(event)
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

  def python_log_record_details(event)
    context = event_context_hash(event)
    normalize_hash(context["log_record"] || context[:log_record])
  end

  def event_exception_data(event)
    context = event_context_hash(event)
    normalize_hash(context["exception"] || context[:exception])
  end

  def event_backtrace(exception_data)
    exception_hash = normalize_hash(exception_data)
    exception_hash["backtrace"] || exception_hash[:backtrace]
  end

  def event_local_variables(exception_data)
    exception_hash = normalize_hash(exception_data)
    normalize_hash(
      exception_hash["locals"] ||
      exception_hash[:locals] ||
      exception_hash["local_variables"] ||
      exception_hash[:local_variables]
    )
  end

  def event_instance_variables(exception_data)
    exception_hash = normalize_hash(exception_data)
    normalize_hash(exception_hash["instance_variables"] || exception_hash[:instance_variables])
  end

  def event_stacktrace_tab_label(project, event)
    if (project.integration_python? || project.integration_javascript?) && event.log?
      "Details"
    else
      "Stacktrace"
    end
  end

  def event_stacktrace_partial(project, event)
    if project.integration_python? && event.log?
      "project_events/python_log_event"
    elsif project.integration_javascript? && event.log?
      "project_events/javascript_log_event"
    elsif project.integration_cfml?
      "project_events/cfml_stacktrace"
    elsif project.integration_javascript?
      "project_events/javascript_stacktrace"
    elsif project.integration_python?
      "project_events/python_stacktrace"
    else
      "project_events/ruby_stacktrace"
    end
  end

  def python_activity_summary(event)
    return nil unless event.respond_to?(:context)

    logger = python_logger_details(event)
    execution = python_execution_details(event)

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

  def javascript_exception_stack(exception_data)
    exception_hash = normalize_hash(exception_data)
    stack = exception_hash["stack"] || exception_hash[:stack]
    return stack.to_s if stack.present?

    backtrace = exception_hash["backtrace"] || exception_hash[:backtrace]
    Array(backtrace).join("\n")
  end

  def javascript_exception_frames(exception_data)
    exception_hash = normalize_hash(exception_data)
    frames = exception_hash["frames"] || exception_hash[:frames]
    return parse_backtrace_frames(frames) if frames.present?

    stack = javascript_exception_stack(exception_data)
    lines = stack.to_s.lines.map(&:strip).reject(&:blank?)
    lines = lines.drop(1) if lines.first&.match?(/\A[\w$.]+(?::|Error)/)
    parse_backtrace_frames(lines)
  end

  def javascript_exception_summary(exception_data, fallback_message = nil)
    exception_hash = normalize_hash(exception_data)
    stack_lines = javascript_exception_stack(exception_data).to_s.lines.map(&:strip)
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

  def javascript_exception_chain(exception_data, chain = [], label: "cause")
    exception_hash = normalize_hash(exception_data)
    return chain unless exception_hash.present?

    cause = normalize_hash(exception_hash["cause"] || exception_hash[:cause])
    if cause.present?
      chain << {
        label: label,
        class_name: cause["class"].presence || cause[:class].presence || cause["name"].presence || cause[:name].presence,
        message: cause["message"].presence || cause[:message].presence,
        frames: javascript_exception_frames(cause)
      }
      javascript_exception_chain(cause, chain, label: "cause")
    end

    context = normalize_hash(exception_hash["context"] || exception_hash[:context])
    if context.present?
      nested_values = context["values"] || context[:values]
      if nested_values.is_a?(Array)
        nested_values.each do |entry|
          next unless entry.is_a?(Hash)

          chain << {
            label: "context",
            class_name: entry["class"].presence || entry[:class].presence || "JavaScript Error",
            message: entry["message"].presence || entry[:message].presence,
            frames: javascript_exception_frames(entry)
          }
        end
      else
        chain << {
          label: "context",
          class_name: context["class"].presence || context[:class].presence,
          message: context["message"].presence || context[:message].presence,
          frames: javascript_exception_frames(context)
        }
      end
    end

    chain.compact_blank
  end

  def javascript_runtime_details(event)
    context = event_context_hash(event)
    headers = normalize_hash(first_hash_value(context, :headers))

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
      url: first_scalar_value(context, :url),
      request_id: first_scalar_value(context, :request_id)
    }
  end

  def javascript_logger_details(event)
    context = event_context_hash(event)
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

  def javascript_log_record_details(event)
    context = event_context_hash(event)
    normalize_hash(context["log_record"] || context[:log_record])
  end

  def javascript_activity_summary(event)
    return nil unless event.respond_to?(:context)

    logger = javascript_logger_details(event)
    runtime = javascript_runtime_details(event)
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

  def cfml_request_details(event)
    context = event_context_hash(event)
    cgi = normalize_hash(context["cgi"] || context[:cgi] || context["CGI"] || context[:CGI])
    generic_request = request_context_details(event)

    {
      script_name: value_from_hash(cgi, "script_name") || value_from_hash(cgi, "SCRIPT_NAME"),
      request_method: value_from_hash(cgi, "request_method") || value_from_hash(cgi, "REQUEST_METHOD") || generic_request[:http_method],
      query_string: value_from_hash(cgi, "query_string") || value_from_hash(cgi, "QUERY_STRING"),
      remote_addr: value_from_hash(cgi, "remote_addr") || value_from_hash(cgi, "REMOTE_ADDR") || generic_request[:client_ip],
      http_user_agent: value_from_hash(cgi, "http_user_agent") || value_from_hash(cgi, "HTTP_USER_AGENT"),
      url: generic_request[:url]
    }
  end

  def source_excerpt_for_frame(frame, radius: 4)
    return nil unless frame.is_a?(Hash)

    absolute_path = frame[:absolute_path]
    line_number = frame[:line_number].to_i
    return nil if absolute_path.blank? || line_number <= 0 || !File.file?(absolute_path)

    lines = File.readlines(absolute_path, chomp: true)
    return nil if lines.empty?

    start_line = [ line_number - radius, 1 ].max
    end_line = [ line_number + radius, lines.length ].min

    {
      path: frame[:file],
      highlight_line: line_number,
      lines: (start_line..end_line).map { |n| { number: n, code: lines[n - 1].to_s } }
    }
  rescue StandardError
    nil
  end

  def seo_title
    page_title = content_for(:title).to_s.strip
    return "Logister" if page_title.blank?

    "#{page_title} | Logister"
  end

  def seo_description
    content_for(:meta_description).to_s.strip.presence ||
      "Logister is an open source error tracking and observability tool for Ruby, JavaScript, TypeScript, and CFML apps."
  end

  def seo_robots
    explicit = content_for(:meta_robots).to_s.strip
    return explicit if explicit.present?

    user_signed_in? ? "noindex, nofollow" : "index, follow"
  end

  def seo_canonical_url
    canonical_path = content_for(:canonical_path).to_s.strip
    if canonical_path.present?
      absolute_url_for(canonical_path)
    else
      absolute_url_for(request.path)
    end
  end

  def seo_og_type
    content_for(:og_type).to_s.strip.presence || "website"
  end

  def seo_og_image
    image_path = content_for(:og_image).to_s.strip.presence || "/icon.png"
    absolute_url_for(image_path)
  end

  def seo_json_ld
    content_for(:json_ld).to_s
  end

  def json_ld(value)
    ERB::Util.json_escape(value.to_json)
  end

  # Renders a <time> tag with UTC datetime; JS (local_time_controller) formats it in the user's timezone.
  # format: :short (date + time), :long (+ seconds), :date_only
  def local_time_tag(time, format: :short)
    return "" if time.blank?

    utc_time = time.utc
    iso = utc_time.iso8601(3)
    fallback = case format
    when :date_only then utc_time.strftime("%b %-d, %Y")
    when :long then utc_time.strftime("%b %-d, %Y %H:%M:%S")
    else utc_time.strftime("%b %-d, %H:%M")
    end
    content_tag(:time, fallback, datetime: iso, data: { local_time: "true", format: format }, class: "local-time")
  end

  def app_icon(name, css: "w-4 h-4")
    path = ICON_PATHS[name.to_sym]
    return "" if path.blank?

    content_tag(:svg, class: css, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "currentColor", aria: { hidden: true }) do
      content_tag(:path, nil, d: path)
    end
  end

  def app_stylesheet_tags
    return "".html_safe unless tailwind_built?

    stylesheet_link_tag("tailwind", media: "all", "data-turbo-track": "reload")
  end

  def app_javascript_tags
    javascript_importmap_tags
  end

  def docs_site_url(section = :overview)
    path = DOCS_PATHS.fetch(section.to_sym)
    "#{DOCS_BASE_URL}#{path}"
  end

  def docs_site_host
    DOCS_BASE_URL
  end

  # True when tailwindcss-rails has built app/assets/builds/tailwind.css.
  # Lets request specs pass without running bin/rails tailwindcss:build.
  def tailwind_built?
    File.exist?(Rails.root.join("app/assets/builds/tailwind.css"))
  end

  private

  def absolute_url_for(path)
    return path if path.start_with?("http://", "https://")

    "#{public_base_url}#{path.start_with?("/") ? path : "/#{path}"}"
  end

  def public_base_url
    url_options = Rails.application.routes.default_url_options.symbolize_keys
    host = url_options[:host].presence
    return request.base_url if host.blank?

    protocol = url_options[:protocol].presence || request.protocol.delete_suffix("://")
    port = url_options[:port].presence

    base_url = +"#{protocol}://#{host}"
    base_url << ":#{port}" if port.present?
    base_url
  end

  def event_context_hash(event)
    raw = event.respond_to?(:context) ? event.context : event
    normalize_hash(raw)
  end

  def normalize_hash(value)
    value.is_a?(Hash) ? value : {}
  end

  def first_hash_value(context, key)
    REQUEST_DETAIL_KEYS.fetch(key).each do |path|
      value = dig_context(context, path)
      return value if value.is_a?(Hash)
    end

    {}
  end

  def first_scalar_value(context, key)
    REQUEST_DETAIL_KEYS.fetch(key).each do |path|
      value = dig_context(context, path)
      return value.to_s if scalarish?(value) && value.to_s.present?
    end

    nil
  end

  def value_from_hash(hash, key)
    return nil unless hash.is_a?(Hash)

    hash[key].presence || hash[key.downcase].presence || hash[key.upcase].presence || hash[key.to_sym].presence
  end

  def dig_context(hash, path)
    current = hash
    path.each do |segment|
      return nil unless current.is_a?(Hash)

      current = current[segment] || current[segment.to_sym]
    end

    current
  end

  def scalarish?(value)
    value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
  end

  def parse_backtrace_line(line)
    patterns = [
      /\Aat (?:(?<method>.+?) )?\((?<file>.+?):(?<line>\d+):(?<column>\d+)\)\z/,
      /\Aat (?<file>.+?):(?<line>\d+):(?<column>\d+)\z/,
      /\A(?<method>[^@]+)@(?<file>.+?):(?<line>\d+):(?<column>\d+)\z/,
      /\A\s*File "(?<file>.+?)", line (?<line>\d+)(?:, in (?<method>.+))?\z/,
      /\A(?<file>.+?):(?<line>\d+)(?::in `(?<method>[^']+)')?\z/,
      /\A(?<file>.+?):(?<line>\d+)(?::in (?<method>.+))?\z/
    ]

    match = patterns.lazy.map { |pattern| pattern.match(line) }.find(&:present?)
    return nil unless match

    {
      file: match[:file].to_s,
      line_number: match[:line].to_i,
      method_name: match[:method].to_s.presence,
      column_number: match.names.include?("column") && match[:column].to_i.positive? ? match[:column].to_i : nil
    }
  end

  def parse_structured_backtrace_frame(frame)
    file = value_from_hash(frame, "filename") ||
      value_from_hash(frame, "template") ||
      value_from_hash(frame, "file") ||
      value_from_hash(frame, "path")
    line_number = value_from_hash(frame, "lineno") ||
      value_from_hash(frame, "line") ||
      value_from_hash(frame, "line_number") ||
      value_from_hash(frame, "lineNumber")
    return nil if file.blank? || line_number.to_i <= 0

    {
      file: file.to_s,
      line_number: line_number.to_i,
      column_number: value_from_hash(frame, "colno") ||
        value_from_hash(frame, "column") ||
        value_from_hash(frame, "column_number") ||
        value_from_hash(frame, "colNumber"),
      method_name: value_from_hash(frame, "function") ||
        value_from_hash(frame, "name") ||
        value_from_hash(frame, "method") ||
        value_from_hash(frame, "module") ||
        value_from_hash(frame, "type"),
      code_context: value_from_hash(frame, "codePrintPlain") ||
        value_from_hash(frame, "code_print_plain") ||
        value_from_hash(frame, "codePrintHTML") ||
        value_from_hash(frame, "line") ||
        value_from_hash(frame, "code_context") ||
        value_from_hash(frame, "context_line") ||
        value_from_hash(frame, "source") ||
        value_from_hash(frame, "code"),
      locals: normalize_hash(value_from_hash(frame, "locals")),
      raw: "#{file}:#{line_number}"
    }
  end

  def absolute_source_path(file_path)
    return nil if file_path.blank?

    root = Rails.root.to_s
    if file_path.start_with?("/")
      return file_path if file_path.start_with?(root)

      return nil
    end

    return nil unless file_path.start_with?("app/", "lib/", "config/", "db/")

    Rails.root.join(file_path).to_s
  end

  def application_frame_path?(relative_path, absolute_path)
    return true if relative_path.to_s.start_with?("app/")

    absolute_path.to_s.start_with?(Rails.root.join("app").to_s)
  end
end
