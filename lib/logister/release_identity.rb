# frozen_string_literal: true

require "digest"
require "pathname"
require "yaml"
require_relative "release_impact"

module Logister
  class ReleaseIdentity
    VERSION_PATTERN = /\A[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z.-]+)?\z/
    GIT_SHA_PATTERN = /\A[0-9a-f]{40}\z/

    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors.freeze
        super(errors.join("\n"))
      end
    end

    Result = Data.define(
      :version,
      :tag,
      :release_date,
      :release_notes,
      :prerelease,
      :make_latest,
      :contract_sha256
    )

    def initialize(repo_root:)
      @repo_root = Pathname(repo_root).expand_path
      @errors = []
    end

    def validate!
      release_config = load_yaml("config/release.yml", "release config")
      ecosystem = load_yaml("config/ecosystem.yml", "ecosystem manifest")
      version = read_version(release_config)
      changelog = read_changelog(release_config)
      heading = changelog_heading(changelog)
      validate_changelog_version(version, heading)
      validate_ecosystem_version_source(ecosystem, release_config)
      validate_openapi_version(version)
      contract_sha256 = contract_digests(ecosystem)

      raise ValidationError, errors if errors.any?

      tag_prefix = release_config.fetch("tag_prefix", "v")
      tag = "#{tag_prefix}#{version}"
      Result.new(
        version: version,
        tag: tag,
        release_date: heading.fetch(:date),
        release_notes: release_notes(changelog, heading.fetch(:start)),
        prerelease: version.include?("-"),
        make_latest: !version.include?("-") && release_config.dig("github", "make_latest") == true,
        contract_sha256: contract_sha256.freeze
      )
    end

    def validate_git_sha!(git_sha)
      return git_sha if git_sha.to_s.match?(GIT_SHA_PATTERN)

      raise ValidationError, [ "Git SHA must be a full lowercase 40-character commit SHA." ]
    end

    private

    attr_reader :repo_root, :errors

    def load_yaml(relative_path, label)
      value = YAML.safe_load_file(repo_root.join(relative_path), permitted_classes: [], permitted_symbols: [], aliases: false)
      return value if value.is_a?(Hash)

      errors << "#{label} #{relative_path} must contain a YAML object."
      {}
    rescue Errno::ENOENT
      errors << "#{label} not found: #{relative_path}."
      {}
    rescue Psych::Exception => e
      errors << "#{label} #{relative_path} is invalid YAML: #{e.message.lines.first.to_s.strip}"
      {}
    end

    def read_version(release_config)
      relative_path = release_config.fetch("version_path", "VERSION")
      version = repo_root.join(relative_path).read.strip
      errors << "#{relative_path} must contain one release version." unless version.match?(VERSION_PATTERN)
      version
    rescue Errno::ENOENT
      errors << "Version source not found: #{relative_path}."
      ""
    end

    def read_changelog(release_config)
      relative_path = release_config.fetch("changelog_path", "CHANGELOG.md")
      repo_root.join(relative_path).read
    rescue Errno::ENOENT
      errors << "Changelog not found: #{relative_path}."
      ""
    end

    def changelog_heading(changelog)
      match = changelog.match(/^##\s+(v[0-9][^\s]*)\s+-\s+([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$/)
      unless match
        errors << "CHANGELOG.md must begin with a versioned release heading."
        return { tag: "", date: "", start: 0 }
      end

      { tag: match[1], date: match[2], start: match.begin(0) }
    end

    def validate_changelog_version(version, heading)
      return if version.empty?
      return if heading.fetch(:tag) == "v#{version}"

      errors << "VERSION #{version.inspect} does not match the first changelog release #{heading.fetch(:tag).inspect}."
    end

    def validate_ecosystem_version_source(ecosystem, release_config)
      declared_path = ecosystem.dig("backend", "version_source", "path")
      declared_format = ecosystem.dig("backend", "version_source", "format")
      expected_path = release_config.fetch("version_path", "VERSION")
      return if declared_path == expected_path && declared_format == "plain_text"

      errors << "config/ecosystem.yml must declare backend version source #{expected_path} as plain_text."
    end

    def validate_openapi_version(version)
      openapi = load_yaml("docs/openapi.yaml", "OpenAPI contract")
      declared = openapi.dig("info", "version").to_s
      return if version.empty? || declared == version

      errors << "OpenAPI info.version #{declared.inspect} does not match VERSION #{version.inspect}."
    end

    def contract_digests(ecosystem)
      contracts = ecosystem.fetch("contracts", {})
      unless contracts.is_a?(Hash) && contracts.any?
        errors << "Ecosystem manifest must declare contracts."
        return {}
      end

      contracts.to_h do |id, contract|
        paths = contract.is_a?(Hash) ? contract["source_files"] : nil
        unless paths.is_a?(Array) && paths.any?
          errors << "Contract #{id} must declare source_files."
          next [ id, nil ]
        end

        [ id, ReleaseImpact.contract_digest(repo_root: repo_root, paths: paths) ]
      rescue ReleaseImpact::ValidationError => e
        errors.concat(e.errors)
        [ id, nil ]
      end
    end

    def release_notes(changelog, release_start)
      following_heading = changelog.index(/^##\s+/, release_start + 1)
      changelog[release_start...(following_heading || changelog.length)].to_s.strip
    end
  end
end
