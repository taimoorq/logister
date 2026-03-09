module ApplicationHelper
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
      parsed = parse_backtrace_line(line.to_s)
      next if parsed.blank?

      absolute_path = absolute_source_path(parsed[:file])
      app_frame = application_frame_path?(parsed[:file], absolute_path)

      {
        raw: line.to_s,
        file: parsed[:file],
        line_number: parsed[:line_number],
        method_name: parsed[:method_name],
        absolute_path: absolute_path,
        application_frame: app_frame
      }
    end
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
      "Logister is a free bug capture tool for Ruby on Rails apps using the logister-ruby gem."
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
      "#{request.base_url}#{request.path}"
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
    value.to_json
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

  # True when tailwindcss-rails has built app/assets/builds/tailwind.css.
  # Lets request specs pass without running bin/rails tailwindcss:build.
  def tailwind_built?
    File.exist?(Rails.root.join("app/assets/builds/tailwind.css"))
  end

  private

  def absolute_url_for(path)
    return path if path.start_with?("http://", "https://")

    "#{request.base_url}#{path.start_with?("/") ? path : "/#{path}"}"
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
      /\A(?<file>.+?):(?<line>\d+)(?::in `(?<method>[^']+)')?\z/,
      /\A(?<file>.+?):(?<line>\d+)(?::in (?<method>.+))?\z/
    ]

    match = patterns.lazy.map { |pattern| pattern.match(line) }.find(&:present?)
    return nil unless match

    {
      file: match[:file].to_s,
      line_number: match[:line].to_i,
      method_name: match[:method].to_s.presence
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
