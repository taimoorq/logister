# frozen_string_literal: true

require "uri"

# Deployment metadata arrives from ingest keys and event context, so any URL it
# carries is untrusted. Only http(s) links to the configured GitHub web host or
# github.com are kept; everything else falls back to links Logister builds.
module ProjectDeploymentUrlPolicy
  PULL_REQUEST_NUMBER_PATTERN = /\A\d{1,10}\z/
  DEFAULT_GITHUB_HOST = "github.com"

  module_function

  def github_url(value)
    candidate = value.is_a?(String) ? value.strip : nil
    return if candidate.blank?

    uri = URI.parse(candidate)
    return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?
    return unless allowed_hosts.include?(uri.host.downcase)

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def pull_request_number(value)
    candidate = value.to_s.strip
    candidate if candidate.match?(PULL_REQUEST_NUMBER_PATTERN)
  end

  def allowed_hosts
    configured_host =
      begin
        URI.parse(Logister::GithubAppConfig.web_url.to_s).host
      rescue URI::InvalidURIError
        nil
      end

    [ configured_host, DEFAULT_GITHUB_HOST ].compact_blank.map(&:downcase).uniq
  end
end
