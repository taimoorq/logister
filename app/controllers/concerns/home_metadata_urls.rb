# frozen_string_literal: true

module HomeMetadataUrls
  extend ActiveSupport::Concern

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
