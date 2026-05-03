module ApplicationHelper
  include ProjectEvents::PayloadSupport

  DOCS_BASE_URL = ENV.fetch("LOGISTER_DOCS_URL", "https://docs.logister.org").chomp("/").freeze
  DOCS_PATHS = {
    overview: "/",
    getting_started: "/getting-started/",
    product: "/product/",
    self_hosting: "/self-hosting/",
    local_development: "/local-development/",
    deployment: "/deployment/",
    clickhouse: "/clickhouse/",
    http_api: "/http-api/",
    ruby_integration: "/integrations/ruby/",
    cfml_integration: "/integrations/cfml/",
    javascript_integration: "/integrations/javascript/",
    python_integration: "/integrations/python/",
    dotnet_integration: "/integrations/dotnet/"
  }.freeze

  STREAMLINE_ICON_SPRITE = "streamline-freehand.svg"
  STREAMLINE_ICON_ALIASES = YAML.safe_load_file(
    Rails.root.join("config/streamline_icons.yml"),
    aliases: false
  ).transform_keys(&:to_sym).freeze
  PROJECT_INTEGRATION_ICON_NAMES = {
    "ruby" => :project_ruby,
    "cfml" => :project_cfml,
    "javascript" => :project_javascript,
    "python" => :project_python,
    "dotnet" => :project_dotnet
  }.freeze

  def request_context_details(event)
    ProjectEvents::RequestContextPresenter.new(event).details
  end

  def pretty_context_json(value)
    JSON.pretty_generate(value)
  rescue StandardError
    value.to_s
  end

  def cfml_exception_frames(exception_data)
    ProjectEvents::CfmlEventPresenter.new(nil, exception_data).frames
  end

  def cfml_exception_summary(exception_data, fallback_message = nil)
    ProjectEvents::CfmlEventPresenter.new(nil, exception_data).summary(fallback_message)
  end

  def python_exception_frames(exception_data)
    ProjectEvents::PythonEventPresenter.new(nil, exception_data).frames
  end

  def python_exception_summary(exception_data, fallback_message = nil)
    ProjectEvents::PythonEventPresenter.new(nil, exception_data).summary(fallback_message)
  end

  def python_exception_chain(exception_data, chain = [], label: "cause")
    chain + ProjectEvents::PythonEventPresenter.new(nil, exception_data).exception_chain
  end

  def python_runtime_details(event)
    ProjectEvents::PythonEventPresenter.new(event).runtime_details
  end

  def python_execution_details(event)
    ProjectEvents::PythonEventPresenter.new(event).execution_details
  end

  def python_logger_details(event)
    ProjectEvents::PythonEventPresenter.new(event).logger_details
  end

  def python_log_record_details(event)
    ProjectEvents::PythonEventPresenter.new(event).log_record_details
  end

  def python_traceback_text(exception_data, fallback_message = nil)
    ProjectEvents::PythonEventPresenter.new(nil, exception_data).traceback_text(fallback_message)
  end

  def python_custom_context_details(event)
    ProjectEvents::PythonEventPresenter.new(event).custom_context_details
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
    if (project.integration_python? || project.integration_javascript? || project.integration_dotnet?) && event.log?
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
    elsif project.integration_dotnet? && event.log?
      "project_events/dotnet_log_event"
    elsif project.integration_cfml?
      "project_events/cfml_stacktrace"
    elsif project.integration_javascript?
      "project_events/javascript_stacktrace"
    elsif project.integration_python?
      "project_events/python_stacktrace"
    elsif project.integration_dotnet?
      "project_events/dotnet_stacktrace"
    else
      "project_events/ruby_stacktrace"
    end
  end

  def python_activity_summary(event)
    return nil unless event.respond_to?(:context)

    ProjectEvents::PythonEventPresenter.new(event).activity_summary
  end

  def javascript_exception_stack(exception_data)
    ProjectEvents::JavascriptEventPresenter.new(nil, exception_data).stack
  end

  def javascript_exception_frames(exception_data)
    ProjectEvents::JavascriptEventPresenter.new(nil, exception_data).frames
  end

  def javascript_exception_summary(exception_data, fallback_message = nil)
    ProjectEvents::JavascriptEventPresenter.new(nil, exception_data).summary(fallback_message)
  end

  def javascript_exception_chain(exception_data, chain = [], label: "cause")
    chain + ProjectEvents::JavascriptEventPresenter.new(nil, exception_data).exception_chain
  end

  def javascript_runtime_details(event)
    ProjectEvents::JavascriptEventPresenter.new(event).runtime_details
  end

  def javascript_logger_details(event)
    ProjectEvents::JavascriptEventPresenter.new(event).logger_details
  end

  def javascript_log_record_details(event)
    ProjectEvents::JavascriptEventPresenter.new(event).log_record_details
  end

  def javascript_activity_summary(event)
    return nil unless event.respond_to?(:context)

    ProjectEvents::JavascriptEventPresenter.new(event).activity_summary
  end

  def dotnet_exception_frames(exception_data)
    ProjectEvents::DotnetEventPresenter.new(nil, exception_data).frames
  end

  def dotnet_exception_summary(exception_data, fallback_message = nil)
    ProjectEvents::DotnetEventPresenter.new(nil, exception_data).summary(fallback_message)
  end

  def dotnet_exception_chain(exception_data, chain = [])
    chain + ProjectEvents::DotnetEventPresenter.new(nil, exception_data).exception_chain
  end

  def dotnet_exception_data(exception_data)
    ProjectEvents::DotnetEventPresenter.new(nil, exception_data).exception_data
  end

  def dotnet_runtime_details(event)
    ProjectEvents::DotnetEventPresenter.new(event).runtime_details
  end

  def dotnet_execution_details(event)
    ProjectEvents::DotnetEventPresenter.new(event).execution_details
  end

  def dotnet_logger_details(event)
    ProjectEvents::DotnetEventPresenter.new(event).logger_details
  end

  def dotnet_log_record_details(event)
    ProjectEvents::DotnetEventPresenter.new(event).log_record_details
  end

  def dotnet_activity_summary(event)
    return nil unless event.respond_to?(:context)

    ProjectEvents::DotnetEventPresenter.new(event).activity_summary
  end

  def cfml_request_details(event)
    ProjectEvents::CfmlEventPresenter.new(event).request_details
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
      "Logister is an open source error tracking and observability tool for Ruby, .NET, Python, JavaScript, TypeScript, and CFML apps."
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
    icon_key = name.to_sym
    return "" unless STREAMLINE_ICON_ALIASES.key?(icon_key)

    content_tag(:svg, class: css, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "currentColor", focusable: false, aria: { hidden: true }) do
      tag.use(href: "#{asset_path(STREAMLINE_ICON_SPRITE)}#streamline-#{icon_key.to_s.tr('_', '-')}")
    end
  end

  def project_integration_icon(project)
    kind = project.integration_kind.to_s
    icon_name = PROJECT_INTEGRATION_ICON_NAMES.fetch(kind, :projects)

    content_tag(:span, class: "project-type-icon project-type-icon-#{kind}", title: project.integration_label, aria: { label: project.integration_label }) do
      app_icon(icon_name, css: "h-6 w-6")
    end
  end

  def app_stylesheet_tags
    return unless tailwind_built?

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
end
