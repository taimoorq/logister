require "uri"

module Logister
  # Content-Security-Policy sources that come from instance settings, resolved on
  # every request so an admin change to the cookie banner takes effect without a
  # restart. Invalid or non-HTTP values contribute nothing to the policy.
  module ContentSecurityPolicySources
    module_function

    # The exact banner script URL (path-scoped), so a shared CDN host such as
    # cdn.jsdelivr.net does not open script-src to every package it serves.
    def cookie_banner_script_sources
      uri = http_uri(InstanceConfiguration.value("public_site.cookie_banner_script_url"))
      return [] unless uri

      [ "#{origin(uri)}#{uri.path.presence || "/"}" ]
    end

    # The upstream banner API is only contacted by the browser when Logister is
    # not proxying it; the proxy is same-origin and already covered by 'self'.
    def cookie_banner_api_sources
      return [] if InstanceConfiguration.value("public_site.cookie_banner_proxy_enabled")

      uri = http_uri(InstanceConfiguration.value("public_site.cookie_banner_base_url"))
      uri ? [ origin(uri) ] : []
    end

    def http_uri(value)
      uri = URI.parse(value.to_s.strip)
      uri if %w[http https].include?(uri.scheme) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end

    def origin(uri)
      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme}://#{uri.host}#{port}"
    end
  end
end
