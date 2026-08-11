# frozen_string_literal: true

require "pathname"
require "json"
require "rubygems/version"
require "yaml"

module Logister
  class ReleaseSet
    VERSION_PATTERN = /\A[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z.-]+)?\z/
    ID_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    ALLOWED_BUMPS = %w[none patch minor major].freeze
    NON_PUBLIC_PATTERNS = {
      "private key material" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
      "credential" => /\b(?:gh[opusr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|npm_[A-Za-z0-9_-]{20,}|pypi-[A-Za-z0-9_-]{20,})\b/,
      "local user path" => %r{(?:/(?:Users)/|/(?:home)/[^/\s]+/|[A-Za-z]:\\(?:Users)\\)}
    }.freeze

    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors.freeze
        super(errors.join("\n"))
      end
    end

    def initialize(repo_root:, release_set_path:)
      @repo_root = Pathname(repo_root).expand_path
      @release_set_path = Pathname(release_set_path).expand_path
      @errors = []
    end

    def validate!
      release_set = load_yaml(release_set_path, "release set")
      ecosystem = load_yaml(repo_root.join("config/ecosystem.yml"), "ecosystem manifest")
      validate_public_metadata(release_set)
      validate_top_level(release_set)
      validate_backend(release_set.fetch("backend", {}))
      validate_impacts(release_set.fetch("impact_records", []))
      validate_components(release_set.fetch("components", {}), ecosystem.fetch("addons", {}))
      validate_catalog(release_set)

      raise ValidationError, errors if errors.any?

      release_set
    end

    private

    attr_reader :repo_root, :release_set_path, :errors

    def load_yaml(path, label)
      value = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
      return value if value.is_a?(Hash)

      errors << "#{label} #{path} must contain a YAML object."
      {}
    rescue Errno::ENOENT
      errors << "#{label} not found: #{path}."
      {}
    rescue Psych::Exception => e
      errors << "#{label} #{path} is invalid YAML: #{e.message.lines.first.to_s.strip}"
      {}
    end

    def validate_top_level(release_set)
      validate_exact_keys(release_set, %w[schema_version id backend impact_records components], "release set")
      errors << "Release set schema_version must be 1." unless release_set["schema_version"] == 1
      errors << "Release set id is invalid." unless release_set["id"].to_s.match?(ID_PATTERN)
    end

    def validate_backend(backend)
      unless backend.is_a?(Hash)
        errors << "Release set backend must be an object."
        return
      end

      validate_exact_keys(backend, %w[version tag], "release set backend")
      version = backend["version"].to_s
      errors << "Backend version is invalid." unless version.match?(VERSION_PATTERN)
      errors << "Backend tag must be v#{version}." unless backend["tag"] == "v#{version}"
      packaged_version = repo_root.join("VERSION").read.strip
      current_release_set = release_set_path.basename.to_s == "v#{packaged_version}.yml"
      if current_release_set && version != packaged_version
        errors << "Backend release-set version #{version} does not match VERSION #{packaged_version}."
      end
    rescue Errno::ENOENT
      errors << "Backend VERSION source is missing."
    end

    def validate_impacts(impact_ids)
      unless impact_ids.is_a?(Array) && impact_ids.any? && impact_ids.uniq == impact_ids
        errors << "Release set impact_records must be a non-empty unique array."
        return
      end

      known_ids = Dir[repo_root.join("config/release-impact/*.yml")].filter_map do |path|
        YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)["id"]
      end
      unknown = impact_ids - known_ids
      errors << "Release set references unknown impact records: #{unknown.join(", ")}." if unknown.any?
    end

    def validate_components(components, addons)
      unless components.is_a?(Hash)
        errors << "Release set components must be an object."
        return
      end

      missing = addons.keys - components.keys
      extra = components.keys - addons.keys
      errors << "Release set omits ecosystem add-ons: #{missing.join(", ")}." if missing.any?
      errors << "Release set contains unknown add-ons: #{extra.join(", ")}." if extra.any?

      components.each do |id, component|
        validate_component(id, component, addons[id])
      end
    end

    def validate_catalog(release_set)
      path = repo_root.join("config/ecosystem-versions.json")
      catalog = JSON.parse(path.read)
      errors << "Published version catalog schema_version must be 1." unless catalog["schema_version"] == 1
      addons = catalog["addons"]
      components = release_set.fetch("components", {})
      unless addons.is_a?(Hash)
        errors << "Published version catalog addons must be an object."
        return
      end

      missing = components.keys - addons.keys
      extra = addons.keys - components.keys
      errors << "Published version catalog omits add-ons: #{missing.join(", ")}." if missing.any?
      errors << "Published version catalog contains unknown add-ons: #{extra.join(", ")}." if extra.any?
      components.each do |id, component|
        published = addons.dig(id, "version").to_s
        allowed = [ component["baseline_version"], component["target_version"] ]
        errors << "Published #{id} version #{published.inspect} is outside this release set." unless allowed.include?(published)
      end

      backend = catalog.dig("backend", "version").to_s
      target = release_set.dig("backend", "version").to_s
      unless backend.match?(VERSION_PATTERN) && Gem::Version.new(backend) <= Gem::Version.new(target)
        errors << "Published backend version #{backend.inspect} is invalid for target #{target}."
      end
    rescue Errno::ENOENT
      errors << "Published version catalog is missing."
    rescue JSON::ParserError => e
      errors << "Published version catalog is invalid JSON: #{e.message}"
    end

    def validate_component(id, component, addon)
      unless component.is_a?(Hash)
        errors << "Release component #{id} must be an object."
        return
      end

      keys = %w[repository baseline_version target_version bump release_required reason channels]
      validate_exact_keys(component, keys, "release component #{id}")
      errors << "Release component #{id} repository does not match the ecosystem manifest." if addon && component["repository"] != addon["repository"]
      errors << "Release component #{id} channels do not match the ecosystem manifest." if addon && component["channels"] != addon["channels"]
      errors << "Release component #{id} release_required must be true or false." unless [ true, false ].include?(component["release_required"])
      reason = component["reason"]
      errors << "Release component #{id} reason must be 12..500 characters." unless reason.is_a?(String) && reason.strip.length.between?(12, 500)
      validate_version_bump(id, component)
    end

    def validate_version_bump(id, component)
      baseline = component["baseline_version"].to_s
      target = component["target_version"].to_s
      bump = component["bump"]
      unless baseline.match?(VERSION_PATTERN) && target.match?(VERSION_PATTERN)
        errors << "Release component #{id} has an invalid version."
        return
      end
      unless ALLOWED_BUMPS.include?(bump)
        errors << "Release component #{id} bump is invalid."
        return
      end

      baseline_segments = Gem::Version.new(baseline).segments.fill(0, Gem::Version.new(baseline).segments.length...3)
      target_segments = Gem::Version.new(target).segments.fill(0, Gem::Version.new(target).segments.length...3)
      valid = case bump
      when "none"
        target == baseline
      when "patch"
        target_segments[0, 2] == baseline_segments[0, 2] && Gem::Version.new(target) > Gem::Version.new(baseline)
      when "minor"
        target_segments[0] == baseline_segments[0] && target_segments[1] > baseline_segments[1]
      when "major"
        target_segments[0] > baseline_segments[0]
      end
      errors << "Release component #{id} target #{target} is not a #{bump} bump from #{baseline}." unless valid
      errors << "Release component #{id} changes version but is not release_required." if bump != "none" && component["release_required"] != true
    end

    def validate_exact_keys(value, required, label)
      return errors << "#{label} must be an object." unless value.is_a?(Hash)

      missing = required - value.keys
      extra = value.keys - required
      errors << "#{label} is missing: #{missing.join(", ")}." if missing.any?
      errors << "#{label} contains unsupported keys: #{extra.join(", ")}." if extra.any?
    end

    def validate_public_metadata(value, path = [])
      case value
      when Hash
        value.each { |key, nested| validate_public_metadata(nested, [ *path, key ]) }
      when Array
        value.each_with_index { |nested, index| validate_public_metadata(nested, [ *path, index ]) }
      when String
        NON_PUBLIC_PATTERNS.each do |label, pattern|
          errors << "Release set contains #{label} at #{path.join(".")}." if value.match?(pattern)
        end
      end
    end
  end
end
