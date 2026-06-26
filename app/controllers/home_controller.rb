class HomeController < ApplicationController
  include HomeMetadataUrls

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
end
