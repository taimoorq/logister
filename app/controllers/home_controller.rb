class HomeController < ApplicationController
  layout "public", except: %i[robots sitemap]

  def show
    redirect_to dashboard_path if user_signed_in?
  end

  def about
  end

  def privacy
  end

  def cookies
  end

  def terms
  end

  def robots
    @app_sitemap_url = "#{public_base_url}/sitemap.xml"
    @docs_sitemap_url = "#{docs_base_url}/sitemap.xml"

    render layout: false, content_type: "text/plain"
  end

  def sitemap
    @pages = [
      { url: root_url, lastmod: view_mtime("show") },
      { url: about_url, lastmod: view_mtime("about") },
      { url: privacy_url, lastmod: view_mtime("privacy") },
      { url: cookies_url, lastmod: view_mtime("cookies") },
      { url: terms_url, lastmod: view_mtime("terms") },
      { url: root_url + "llms.txt", lastmod: public_file_mtime("llms.txt") },
      { url: root_url + "llms-full.txt", lastmod: public_file_mtime("llms-full.txt") }
    ]

    render layout: false
  end

  private

  def view_mtime(name)
    Rails.root.join("app/views/home/#{name}.html.erb").mtime.to_date.iso8601
  end

  def public_file_mtime(name)
    Rails.root.join("public/#{name}").mtime.to_date.iso8601
  end

  def docs_base_url
    docs_url = ENV["LOGISTER_DOCS_URL"].to_s.strip
    docs_url = "https://logister.org/docs" if docs_url.empty?
    docs_url.chomp("/")
  end

  def public_base_url
    url_options = Rails.application.routes.default_url_options.symbolize_keys
    host = url_options[:host].presence
    return request.base_url.chomp("/") if host.blank?

    raw_protocol = url_options[:protocol].presence || request.protocol
    protocol = raw_protocol.to_s.delete_suffix("://").delete_suffix(":")
    port = url_options[:port].presence

    base_url = +"#{protocol}://#{host}"
    base_url << ":#{port}" if port.present?
    base_url.chomp("/")
  end
end
