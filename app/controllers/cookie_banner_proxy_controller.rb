# frozen_string_literal: true

require "net/http"

class CookieBannerProxyController < ApplicationController
  skip_forgery_protection

  ALLOWED_PROXY_PATH = /\A[A-Za-z0-9._\-\/]+\z/
  REQUEST_TIMEOUT_SECONDS = 5

  def show
    return head :not_found unless valid_proxy_path?

    response = forward_probo_request
    render_probo_response(response)
  rescue StandardError => error
    Rails.logger.warn("Probo cookie banner proxy failed: #{error.class} #{error.message}")
    head :bad_gateway
  end

  private

  def forward_probo_request
    uri = probo_upstream_uri
    request = build_upstream_request(uri)

    Logister::HttpClient.request(
      uri,
      request,
      open_timeout: REQUEST_TIMEOUT_SECONDS,
      read_timeout: REQUEST_TIMEOUT_SECONDS
    )
  end

  def build_upstream_request(uri)
    request_class = request.post? ? Net::HTTP::Post : Net::HTTP::Get
    request_class.new(uri).tap do |upstream_request|
      upstream_request["Accept"] = request.headers["Accept"] if request.headers["Accept"].present?
      upstream_request["Content-Type"] = request.content_type if request.content_type.present?
      upstream_request["User-Agent"] = request.user_agent if request.user_agent.present?
      upstream_request["X-Forwarded-For"] = request.remote_ip if request.remote_ip.present?
      upstream_request["X-Forwarded-Host"] = request.host
      upstream_request["X-Forwarded-Proto"] = request.protocol.delete_suffix("://")
      upstream_request.body = request.raw_post if request.post?
    end
  end

  def render_probo_response(response)
    headers["Cache-Control"] = response["Cache-Control"] if response["Cache-Control"].present?

    render plain: response.body.to_s,
           status: response.code.to_i,
           content_type: response["Content-Type"].presence || "application/json"
  end

  def probo_upstream_uri
    upstream_base_uri.tap do |uri|
      uri.path = [ uri.path.delete_suffix("/"), proxy_path ].reject(&:blank?).join("/")
      uri.query = request.query_string.presence
    end
  end

  def upstream_base_uri
    URI.parse(probo_upstream_base_url).tap do |uri|
      raise URI::InvalidURIError, "Probo cookie banner base URL must use http or https" unless %w[http https].include?(uri.scheme)
      raise URI::InvalidURIError, "Probo cookie banner base URL must include a host" if uri.host.blank?
    end
  end

  def valid_proxy_path?
    return false if probo_upstream_base_url.blank?
    return false if probo_cookie_banner_id.blank?
    return false unless proxy_path.match?(ALLOWED_PROXY_PATH)
    return false if proxy_path.split("/").include?("..")

    proxy_path == probo_cookie_banner_id || proxy_path.start_with?("#{probo_cookie_banner_id}/")
  end

  def proxy_path
    params[:proxy_path].to_s
  end

  def probo_upstream_base_url
    ENV["PROBO_COOKIE_BANNER_BASE_URL"].to_s.strip
  end

  def probo_cookie_banner_id
    ENV["PROBO_COOKIE_BANNER_ID"].to_s.strip
  end
end
