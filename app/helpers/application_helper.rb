module ApplicationHelper
  include ProjectEvents::PayloadSupport

  DOCS_BASE_URL = begin
    docs_url = ENV["LOGISTER_DOCS_URL"].to_s.strip
    docs_url = "https://docs.logister.org" if docs_url.empty?
    docs_url.chomp("/")
  end.freeze
  DOCS_PATHS = {
    overview: "/",
    getting_started: "/getting-started/",
    product: "/product/",
    self_hosting: "/self-hosting/",
    local_development: "/local-development/",
    deployment: "/deployment/",
    clickhouse: "/clickhouse/",
    http_api: "/http-api/",
    api_reference: "/api-reference/",
    metrics: "/metrics/",
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
    "dotnet" => :project_dotnet,
    "cloudflare_pages" => :external,
    "android" => :projects,
    "ios" => :projects,
    "http_api" => :external
  }.freeze

  def layout_theme
    if respond_to?(:user_signed_in?) && user_signed_in?
      :authenticated
    elsif respond_to?(:devise_controller?) && devise_controller?
      :auth
    else
      :public
    end
  end

  def authenticated_layout_theme?
    layout_theme == :authenticated
  end

  def auth_layout_theme?
    layout_theme == :auth
  end

  def public_layout_theme?
    layout_theme == :public
  end

  def layout_body_class
    case layout_theme
    when :authenticated
      "min-h-screen flex flex-col bg-slate-100 text-slate-900 antialiased"
    when :auth
      "auth-theme min-h-screen flex flex-col bg-slate-50 text-slate-800 antialiased"
    else
      "public-shell min-h-screen flex flex-col antialiased"
    end
  end

  def layout_nav_shell_class
    class_names(
      "nav-shell",
      authenticated_layout_theme? ? "bg-[var(--app-nav-bg)] border-b border-[var(--app-nav-border)] sticky top-0 z-20" : "public-nav-shell sticky top-0 z-30"
    )
  end

  def layout_nav_inner_class
    authenticated_layout_theme? ? "w-full px-4 sm:px-6 lg:px-8" : "public-nav-inner"
  end

  def layout_brand_link_class
    class_names(
      "flex items-center gap-2 no-underline font-semibold shrink-0",
      authenticated_layout_theme? ? "text-white hover:text-blue-100" : "public-brand"
    )
  end

  def layout_brand_logo_class
    authenticated_layout_theme? ? "h-6 w-auto" : "public-brand-logo"
  end

  def layout_mobile_toggle_class
    authenticated_layout_theme? ?
      "md:hidden flex items-center justify-center w-11 h-11 -mr-2 rounded-lg text-blue-100 hover:bg-blue-900/60 hover:text-white focus:outline-none focus:ring-2 focus:ring-blue-300 focus:ring-offset-2 focus:ring-offset-[var(--app-nav-bg)]" :
      "public-mobile-toggle md:hidden"
  end

  def layout_nav_panel_class
    class_names(
      "nav-panel",
      authenticated_layout_theme? ?
        "hidden md:flex flex-col md:flex-row md:items-center gap-0 md:gap-1 absolute md:relative top-full left-0 right-0 md:top-0 bg-[var(--app-nav-bg)] md:bg-transparent border-b border-[var(--app-nav-border)] md:border-0 shadow-lg md:shadow-none py-3 md:py-0 px-4 md:px-0" :
        "public-nav-panel hidden md:flex flex-col md:flex-row md:items-center gap-0 md:gap-1 lg:gap-2 absolute md:relative top-full left-0 right-0 md:top-0 md:bg-transparent md:border-0 md:shadow-none md:py-0 md:px-0"
    )
  end

  def layout_main_class
    case layout_theme
    when :authenticated
      "flex-1 w-full px-3 sm:px-4 lg:px-6 py-4 sm:py-5"
    when :auth
      "flex-1 w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8"
    else
      "public-main flex-1 w-full"
    end
  end

  def layout_flash_class(type)
    return "public-flash public-flash-#{type}" if public_layout_theme?

    case type.to_sym
    when :notice
      "mb-4 rounded-lg bg-blue-50 border border-blue-200 px-4 py-3 text-sm text-blue-800"
    else
      "mb-4 rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-800"
    end
  end

  def app_stylesheet_tags(theme = layout_theme)
    tags = []
    tags << stylesheet_link_tag("css/tour.min", media: "all", "data-turbo-track": "reload") if theme.to_sym == :authenticated
    tags << stylesheet_link_tag("tailwind", media: "all", "data-turbo-track": "reload") if tailwind_built?

    safe_join(tags)
  end

  def app_javascript_tags(theme = layout_theme)
    tags = []
    tags << javascript_include_tag("tour", defer: true, "data-turbo-track": "reload") if theme.to_sym == :authenticated
    tags << javascript_importmap_tags(javascript_entrypoint_for(theme))

    safe_join(tags)
  end

  def javascript_entrypoint_for(theme = layout_theme)
    case theme.to_sym
    when :public then "public"
    when :auth then "auth"
    else "authenticated"
    end
  end

  def google_tag_id
    ENV["GOOGLE_TAG_ID"].to_s.strip.presence
  end

  def cloudflare_web_analytics_token
    ENV["CLOUDFLARE_WEB_ANALYTICS_TOKEN"].to_s.strip.presence
  end

  def analytics_enabled?
    Rails.env.production? || ActiveModel::Type::Boolean.new.cast(ENV.fetch("LOGISTER_ANALYTICS_ENABLED", "false"))
  end

  def probo_cookie_banner_script_url
    ENV["PROBO_COOKIE_BANNER_SCRIPT_URL"].to_s.strip.presence || "https://cdn.jsdelivr.net/npm/@probo/cookie-banner/dist/cookie-banner.iife.js"
  end

  def probo_cookie_banner_id
    ENV["PROBO_COOKIE_BANNER_ID"].to_s.strip.presence
  end

  def probo_cookie_banner_upstream_base_url
    ENV["PROBO_COOKIE_BANNER_BASE_URL"].to_s.strip.presence
  end

  def probo_cookie_banner_position
    ENV["PROBO_COOKIE_BANNER_POSITION"].to_s.strip.presence || "bottom-left"
  end

  def probo_cookie_banner_proxy_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("PROBO_COOKIE_BANNER_PROXY_ENABLED", "true"))
  end

  def probo_cookie_banner_base_url
    probo_cookie_banner_proxy_enabled? ? cookie_banner_proxy_base_url : probo_cookie_banner_upstream_base_url
  end

  def probo_cookie_banner_api_configured?
    probo_cookie_banner_proxy_enabled? ? probo_cookie_banner_upstream_base_url.present? : probo_cookie_banner_base_url.present?
  end

  def analytics_cookie_consent_category
    ENV["LOGISTER_ANALYTICS_COOKIE_CATEGORY"].to_s.strip.presence || "analytics"
  end

  def cookie_consent_enabled?
    !Rails.env.test? &&
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("LOGISTER_COOKIE_CONSENT_ENABLED", "true")) &&
      probo_cookie_banner_id.present? &&
      probo_cookie_banner_api_configured?
  end

  def responsive_scroll_region(**options, &block)
    options[:class] = class_names("mobile-x-scroll", options[:class])

    content_tag(:div, capture(&block), options)
  end

  def responsive_chart_region(**options, &block)
    options[:class] = class_names("mobile-chart-scroll", options[:class])

    content_tag(:div, capture(&block), options)
  end

  def event_partition_params(event)
    return {} if event.blank? || !event.has_attribute?(:occurred_at) || event.occurred_at.blank?

    { event_occurred_at: event.occurred_at.utc.iso8601(6) }
  end

  def partitioned_project_event_path(project, event, options = {})
    project_event_path(project, event, event_partition_params(event).merge(options))
  end

  def responsive_scroll_classes(*classes)
    class_names("mobile-x-scroll", classes)
  end

  def request_context_details(event)
    ProjectEvents::RequestContextPresenter.new(event).details
  end

  def request_highlight_target(*candidates, query_string: nil)
    target = candidates.compact_blank.first.to_s.strip
    return nil if target.blank?

    query = query_string.to_s.strip.delete_prefix("?")
    if query.present? && !target.include?("?") && !target.end_with?("?")
      target = "#{target}?#{query}"
    end

    target
  end

  def request_highlight_method(value)
    value.to_s.strip.upcase.presence
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
      "Logister is an open source, self-hosted error monitoring and bug triage tool for Ruby, .NET, Python, JavaScript, TypeScript, and CFML apps."
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

  def docs_site_url(section = :overview)
    path = DOCS_PATHS.fetch(section.to_sym)
    "#{DOCS_BASE_URL}#{path}"
  end

  def docs_site_host
    DOCS_BASE_URL
  end

  def cookie_banner_proxy_base_url
    absolute_url_for("/api/cookie-banner/v1")
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

    raw_protocol = url_options[:protocol].presence || request.protocol
    protocol = raw_protocol.to_s.delete_suffix("://").delete_suffix(":")
    port = url_options[:port].presence

    base_url = +"#{protocol}://#{host}"
    base_url << ":#{port}" if port.present?
    base_url
  end
end
