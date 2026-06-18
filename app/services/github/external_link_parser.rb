# frozen_string_literal: true

require "uri"

module Github
  class ExternalLinkParser
    Result = Data.define(:url, :link_type, :repository_full_name, :external_id, :title)

    PATH_PATTERN = %r{\A/(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)/(?<kind>issues|pull)/(?<number>\d+)(?:/.*)?\z}

    def self.call(url, web_url: Logister::GithubAppConfig.web_url)
      new(url: url, web_url: web_url).call
    end

    def initialize(url:, web_url:)
      @url = url
      @web_url = web_url
    end

    def call
      uri = URI.parse(url.to_s.strip)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?
      return unless allowed_hosts.include?(uri.host.downcase)

      match = PATH_PATTERN.match(uri.path.to_s)
      return unless match

      kind = match[:kind]
      link_type = kind == "pull" ? "pull_request" : "issue"
      repository_full_name = "#{match[:owner]}/#{match[:repo]}"
      number = match[:number]

      Result.new(
        url: canonical_url(uri, repository_full_name, kind, number),
        link_type: link_type,
        repository_full_name: repository_full_name,
        external_id: number,
        title: title_for(repository_full_name, link_type, number)
      )
    rescue URI::InvalidURIError
      nil
    end

    private

    attr_reader :url, :web_url

    def allowed_hosts
      @allowed_hosts ||= [
        URI.parse(web_url.to_s).host,
        "github.com"
      ].compact_blank.map(&:downcase).uniq
    rescue URI::InvalidURIError
      [ "github.com" ]
    end

    def canonical_url(uri, repository_full_name, kind, number)
      canonical = URI::Generic.build(
        scheme: uri.scheme,
        host: uri.host,
        path: "/#{repository_full_name}/#{kind}/#{number}"
      )
      canonical.to_s
    end

    def title_for(repository_full_name, link_type, number)
      type = link_type == "pull_request" ? "PR" : "issue"

      "#{repository_full_name} #{type} ##{number}"
    end
  end
end
