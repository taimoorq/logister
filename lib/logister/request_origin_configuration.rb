# frozen_string_literal: true

require "ipaddr"
require "uri"

module Logister
  # Host authorization and proxy trust read from the environment before Rails
  # finishes booting, so production.rb can configure the middleware.
  module RequestOriginConfiguration
    module_function

    # Hosts Rails accepts. Empty means "do not enforce": neither
    # LOGISTER_PUBLIC_URL nor LOGISTER_ALLOWED_HOSTS was set, which is how a fresh
    # install reaches first-run setup before the operator names its domain.
    def allowed_hosts(env = ENV)
      hosts = []
      public_url = env["LOGISTER_PUBLIC_URL"].to_s.strip
      hosts << URI.parse(public_url).host if public_url.present?
      hosts.concat(list(env["LOGISTER_ALLOWED_HOSTS"]))
      hosts.compact.map(&:downcase).uniq
    rescue URI::InvalidURIError
      raise ArgumentError, "LOGISTER_PUBLIC_URL is not a valid URL"
    end

    # Extra proxies, beyond loopback and private networks, trusted to report the
    # client address in X-Forwarded-For. Nil keeps the Rails default.
    def trusted_proxies(env = ENV)
      proxies = list(env["LOGISTER_TRUSTED_PROXIES"])
      return if proxies.empty?

      ActionDispatch::RemoteIp::TRUSTED_PROXIES + proxies.map do |proxy|
        IPAddr.new(proxy)
      rescue IPAddr::InvalidAddressError
        raise ArgumentError, "LOGISTER_TRUSTED_PROXIES has an invalid address: #{proxy}"
      end
    end

    def list(value)
      value.to_s.split(",").map(&:strip).reject(&:empty?)
    end
  end
end
