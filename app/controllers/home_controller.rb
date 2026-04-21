class HomeController < ApplicationController
  def show
    redirect_to dashboard_path if user_signed_in?
  end

  def about
  end

  def privacy
  end

  def terms
  end

  def sitemap
    @pages = [
      { url: root_url, lastmod: view_mtime("show") },
      { url: docs_url, lastmod: Time.current.to_date.iso8601 },
      { url: docs_ruby_integration_url, lastmod: Time.current.to_date.iso8601 },
      { url: docs_cfml_integration_url, lastmod: Time.current.to_date.iso8601 },
      { url: about_url, lastmod: view_mtime("about") },
      { url: privacy_url, lastmod: view_mtime("privacy") },
      { url: terms_url, lastmod: view_mtime("terms") }
    ]

    render layout: false
  end

  private

  def view_mtime(name)
    Rails.root.join("app/views/home/#{name}.html.erb").mtime.to_date.iso8601
  end
end
