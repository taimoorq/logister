class HomeController < ApplicationController
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
end
