module ApplicationHelper
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
end
