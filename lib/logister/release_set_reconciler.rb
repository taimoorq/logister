# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "pathname"
require "uri"
require_relative "release_identity"
require_relative "release_set"

module Logister
  class ReleaseSetReconciler
    class HttpClient
      MAX_REDIRECTS = 4

      def initialize(github_token: ENV["GITHUB_TOKEN"])
        @github_token = github_token.to_s
      end

      def get(url, redirects: MAX_REDIRECTS)
        raise "too many redirects for #{url}" if redirects.negative?

        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github+json" if uri.host == "api.github.com"
        request["Authorization"] = "Bearer #{@github_token}" if uri.host == "api.github.com" && !@github_token.empty?
        request["User-Agent"] = "Logister public release-set reconciler"
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
          http.request(request)
        end
        if response.is_a?(Net::HTTPRedirection)
          location = URI.join(url, response.fetch("location")).to_s
          return get(location, redirects: redirects - 1)
        end

        [ response.code.to_i, response.body.to_s ]
      end
    end

    def initialize(repo_root:, release_set_path:, http: HttpClient.new)
      @repo_root = Pathname(repo_root).expand_path
      @release_set_path = Pathname(release_set_path).expand_path
      @http = http
      @checks = []
      @errors = []
    end

    def reconcile
      release_set = ReleaseSet.new(repo_root: repo_root, release_set_path: release_set_path).validate!
      identity = ReleaseIdentity.new(repo_root: repo_root).validate!
      reconcile_backend(release_set, identity)
      release_set.fetch("components").each { |id, component| reconcile_component(id, component) }

      {
        schema_version: 1,
        release_set: release_set.fetch("id"),
        status: errors.empty? ? "complete" : "pending",
        backend: {
          version: release_set.dig("backend", "version"),
          tag: release_set.dig("backend", "tag"),
          contract_sha256: identity.contract_sha256
        }.merge(@backend_evidence || {}),
        components: release_set.fetch("components").transform_values do |component|
          {
            version: component.fetch("target_version"),
            release_required: component.fetch("release_required"),
            channels: component.fetch("channels")
          }
        end,
        checks: checks,
        errors: errors
      }
    end

    def catalog(receipt)
      raise "release set is not complete" unless receipt.fetch(:status) == "complete"

      {
        schema_version: 1,
        backend: { version: receipt.dig(:backend, :version) },
        addons: receipt.fetch(:components).to_h do |id, component|
          [ id, { version: component.fetch(:version) } ]
        end
      }
    end

    private

    attr_reader :repo_root, :release_set_path, :http, :checks, :errors

    def reconcile_backend(release_set, identity)
      version = release_set.dig("backend", "version")
      tag = release_set.dig("backend", "tag")
      release = github_release("backend", "taimoorq/logister", tag)
      receipt_asset = Array(release&.fetch("assets", nil)).find { |asset| asset["name"] == "release-receipt.json" }
      receipt_url = receipt_asset&.fetch("browser_download_url", nil)
      if receipt_url.nil?
        fallback_url = "https://github.com/taimoorq/logister/releases/tag/#{tag}"
        checks << { component: "backend", channel: "release_receipt", url: fallback_url, status: "pending" }
        errors << "backend/release_receipt: release-receipt.json is missing"
      else
        check("backend", "release_receipt", receipt_url) do |body|
        receipt = JSON.parse(body)
        raise "receipt version mismatch" unless receipt["version"] == version && receipt["tag"] == tag
        raise "receipt contract mismatch" unless receipt["contract_sha256"] == identity.contract_sha256
        git_sha = receipt["git_sha"]
        raise "receipt Git SHA is invalid" unless git_sha.to_s.match?(ReleaseIdentity::GIT_SHA_PATTERN)
        digest = receipt.dig("container", "digest")
        raise "receipt container digest is invalid" unless digest.to_s.match?(/\Asha256:[0-9a-f]{64}\z/)
        registries = receipt.dig("container", "registries")
        raise "receipt registry references are incomplete" unless registries.is_a?(Hash) && registries.values_at("docker_hub", "ghcr").all? { |value| value.to_s.include?(tag) }
        raise "receipt deployment is not verified" unless receipt.dig("deployment", "verified") == true
        @backend_evidence = {
          git_sha: git_sha,
          container: receipt.fetch("container"),
          deployment: receipt.fetch("deployment")
        }

        true
        end
      end

      check("backend", "runtime", "https://logister.org/health/release") do |body|
        runtime = JSON.parse(body)
        raise "runtime version mismatch" unless runtime["status"] == "ok" && runtime["version"] == version && runtime["tag"] == tag
        raise "runtime contract mismatch" unless runtime["contract_sha256"] == identity.contract_sha256
        if @backend_evidence
          raise "runtime Git SHA mismatch" unless runtime["git_sha"] == @backend_evidence.fetch(:git_sha)
          raise "runtime image digest mismatch" unless runtime["image_digest"] == @backend_evidence.dig(:container, "digest")
        end
        raise "runtime migration verification failed" unless runtime["database"] == { "connected" => true, "migrations_current" => true }

        true
      end
    end

    def reconcile_component(id, component)
      version = component.fetch("target_version")
      repository = component.fetch("repository")
      github_release(id, repository, "v#{version}")
      component.fetch("channels").each do |channel|
        next if channel == "github_release"

        reconcile_channel(id, channel, version)
      end
    end

    def reconcile_channel(id, channel, version)
      case channel
      when "rubygems"
        check(id, channel, "https://rubygems.org/api/v1/versions/logister-ruby.json") do |body|
          JSON.parse(body).any? { |item| item["number"] == version }
        end
      when "npm"
        package = id == "logister-cli" ? "logister-cli" : "logister-js"
        check(id, channel, "https://registry.npmjs.org/#{package}/#{version}") do |body|
          metadata = JSON.parse(body)
          raise "npm version mismatch" unless metadata["version"] == version
          reconcile_cli_distributions(metadata, version) if id == "logister-cli"
          true
        end
      when "pypi"
        check(id, channel, "https://pypi.org/pypi/logister-python/#{version}/json") { |body| JSON.parse(body).dig("info", "version") == version }
      when "nuget_logister", "nuget_logister_aspnetcore"
        package = channel == "nuget_logister" ? "logister" : "logister.aspnetcore"
        check(id, channel, "https://api.nuget.org/v3-flatcontainer/#{package}/index.json") do |body|
          JSON.parse(body).fetch("versions").include?(version.downcase)
        end
      when "maven_central"
        url = "https://repo1.maven.org/maven2/org/logister/logister-android/#{version}/logister-android-#{version}.pom"
        check(id, channel, url) { |body| body.include?("<version>#{version}</version>") }
      when "swift_package_manager"
        checks << { component: id, channel: channel, url: "https://github.com/taimoorq/logister-ios/releases/tag/v#{version}", status: "verified" }
      when "homebrew-logister", "scoop-logister"
        # Both downstreams are verified from the canonical CLI npm metadata in one pass.
      else
        errors << "#{id}/#{channel}: no public reconciliation adapter"
      end
    end

    def reconcile_cli_distributions(metadata, version)
      tarball_url = metadata.dig("dist", "tarball")
      expected_sha1 = metadata.dig("dist", "shasum")
      tarball = fetch(tarball_url)
      raise "CLI npm tarball SHA-1 mismatch" unless Digest::SHA1.hexdigest(tarball) == expected_sha1
      sha256 = Digest::SHA256.hexdigest(tarball)

      check("logister-cli", "homebrew-logister", "https://raw.githubusercontent.com/taimoorq/homebrew-logister/main/Formula/logister.rb") do |body|
        raise "Homebrew npm URL mismatch" unless body.include?(tarball_url)
        raise "Homebrew checksum mismatch" unless body.match?(/^\s*sha256\s+"#{sha256}"\s*$/)
        true
      end
      check("logister-cli", "scoop-logister", "https://raw.githubusercontent.com/taimoorq/scoop-logister/main/bucket/logister.json") do |body|
        manifest = JSON.parse(body)
        raise "Scoop version mismatch" unless manifest["version"] == version
        raise "Scoop npm URL mismatch" unless manifest["url"] == tarball_url
        raise "Scoop checksum mismatch" unless manifest["hash"] == sha256
        true
      end
    end

    def github_release(component, repository, tag)
      url = "https://api.github.com/repos/#{repository}/releases/tags/#{tag}"
      value = nil
      check(component, "github_release", url) do |body|
        parsed = JSON.parse(body)
        raise "GitHub Release tag mismatch" unless parsed["tag_name"] == tag
        raise "GitHub Release is a draft" if parsed["draft"]
        value = parsed
        true
      end
      value
    end

    def check(component, channel, url)
      body = fetch(url)
      verified = yield(body)
      raise "public metadata did not contain the target version" unless verified
      checks << { component: component, channel: channel, url: url, status: "verified" }
      body
    rescue StandardError => e
      checks << { component: component, channel: channel, url: url, status: "pending" }
      errors << "#{component}/#{channel}: #{e.message}"
      nil
    end

    def fetch(url)
      raise "public URL is missing" if url.to_s.empty?

      status, body = http.get(url)
      raise "public endpoint returned HTTP #{status}" unless status.between?(200, 299)

      body
    end
  end
end
