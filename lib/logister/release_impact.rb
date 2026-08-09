# frozen_string_literal: true

require "digest"
require "open3"
require "pathname"
require "shellwords"
require "yaml"

module Logister
  class ReleaseImpact
    ALLOWED_BUMPS = %w[none patch minor major].freeze
    ALLOWED_COMPATIBILITY = %w[compatible expand breaking].freeze
    ALLOWED_ACTIVATION = %w[immediate backend_first_dark after_consumers].freeze
    IMPACT_ID_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    ADDON_ID_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    CONTRACT_ID_PATTERN = /\A[a-z][a-z0-9_]*\z/
    GIT_REF_PATTERN = /\A(?!-)[A-Za-z0-9][A-Za-z0-9._\/-]{0,254}\z/
    SENSITIVE_KEYS = %w[
      api_key credential credentials password private_key secret secrets token tokens
    ].freeze
    NON_PUBLIC_VALUE_PATTERNS = {
      "private key material" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
      "GitHub credential" => /\b(?:gh[opusr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b/,
      "AWS access key" => /\bAKIA[0-9A-Z]{16}\b/,
      "package registry credential" => /\b(?:npm_|pypi-)[A-Za-z0-9_-]{20,}\b/,
      "credential-bearing URL" => /[?&](?:api_?key|password|secret|token)=/i,
      "local user path" => %r{(?:/(?:Users)/|/(?:home)/[^/\s]+/|[A-Za-z]:\\(?:Users)\\)}
    }.freeze
    FILE_MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB

    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors.freeze
        super(errors.join("\n"))
      end
    end

    Result = Data.define(:triggered_contracts, :impact_files, :consumer_decisions, :contract_digests)

    class << self
      def changed_files(repo_root:, base:, head: "HEAD")
        base_ref = validated_git_ref(base)
        head_ref = validated_git_ref(head)
        revision_range = "#{Shellwords.escape(base_ref)}...#{Shellwords.escape(head_ref)}"
        output, error, status = Open3.capture3(
          "git", "-C", repo_root.to_s, "diff", "--name-only", "--diff-filter=ACMRT", revision_range, "--"
        )
        raise ValidationError, [ "Unable to read changed files: #{error.strip}" ] unless status.success?

        output.lines(chomp: true).reject(&:empty?)
      end

      def validated_git_ref(value)
        reference = value.to_s
        return reference if reference.match?(GIT_REF_PATTERN)

        raise ValidationError, [ "Git references must use a bounded branch, tag, or commit name." ]
      end

      def contract_digest(repo_root:, paths:)
        root = Pathname(repo_root).expand_path
        digest = Digest::SHA256.new
        Array(paths).map(&:to_s).sort.each do |relative_path|
          path = root.join(relative_path).cleanpath
          unless path.to_s.start_with?("#{root}/") && path.file?
            raise ValidationError, [ "Contract source is missing or outside the repository: #{relative_path}." ]
          end

          digest << relative_path << "\0" << path.binread << "\0"
        end
        digest.hexdigest
      end
    end

    def initialize(ecosystem_path:, impact_paths:, changed_files: [])
      @ecosystem_path = Pathname(ecosystem_path)
      @impact_paths = impact_paths.map { |path| Pathname(path) }
      @changed_files = changed_files.map(&:to_s).uniq.sort
      @errors = []
    end

    def validate!
      ecosystem = load_yaml(ecosystem_path, "ecosystem manifest")
      validate_ecosystem(ecosystem)
      records = impact_paths.filter_map { |path| load_impact(path) }
      validate_unique_record_ids(records)

      triggered_contracts = triggered_contract_ids(ecosystem)
      validate_required_records(triggered_contracts, records)
      contract_digests = build_contract_digests(ecosystem)
      decisions = validate_records(ecosystem, triggered_contracts, records, contract_digests)

      raise ValidationError, errors if errors.any?

      Result.new(
        triggered_contracts: triggered_contracts.freeze,
        impact_files: impact_paths.map(&:to_s).freeze,
        consumer_decisions: decisions.freeze,
        contract_digests: contract_digests.freeze
      )
    end

    private

    attr_reader :ecosystem_path, :impact_paths, :changed_files, :errors

    def load_yaml(path, label)
      value = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
      return value if value.is_a?(Hash)

      errors << "#{label} #{path} must contain a YAML object."
      {}
    rescue Errno::ENOENT
      errors << "#{label} not found: #{path}"
      {}
    rescue Psych::Exception => e
      errors << "#{label} #{path} is invalid YAML: #{e.message.lines.first.to_s.strip}"
      {}
    end

    def validate_ecosystem(ecosystem)
      errors << "Ecosystem schema_version must be 1." unless ecosystem["schema_version"] == 1
      validate_public_metadata(ecosystem, "ecosystem manifest")

      addons = ecosystem["addons"]
      contracts = ecosystem["contracts"]
      errors << "Ecosystem addons must be a non-empty object." unless addons.is_a?(Hash) && addons.any?
      errors << "Ecosystem contracts must be a non-empty object." unless contracts.is_a?(Hash) && contracts.any?
      return unless addons.is_a?(Hash) && contracts.is_a?(Hash)

      addons.each do |id, addon|
        validate_identifier(id, ADDON_ID_PATTERN, "add-on")
        unless addon.is_a?(Hash)
          errors << "Add-on #{id} must be an object."
          next
        end

        errors << "Add-on #{id} must declare a public repository." if blank?(addon["repository"])
        errors << "Add-on #{id} must declare a version source." unless addon["version_source"].is_a?(Hash)
        errors << "Add-on #{id} must declare at least one channel." unless addon["channels"].is_a?(Array) && addon["channels"].any?
      end

      contracts.each do |id, contract|
        validate_identifier(id, CONTRACT_ID_PATTERN, "contract")
        unless contract.is_a?(Hash)
          errors << "Contract #{id} must be an object."
          next
        end

        patterns = contract["owned_paths"]
        consumers = contract["consumers"]
        errors << "Contract #{id} must declare owned_paths." unless patterns.is_a?(Array) && patterns.any?
        errors << "Contract #{id} must declare consumers." unless consumers.is_a?(Array) && consumers.any?
        next unless consumers.is_a?(Array)

        unknown = consumers - addons.keys
        errors << "Contract #{id} references unknown consumers: #{unknown.join(", ")}." if unknown.any?
      end
    end

    def load_impact(path)
      record = load_yaml(path, "release-impact record")
      validate_public_metadata(record, "release-impact record #{path}")
      record["__path__"] = path.to_s
      record
    end

    def validate_unique_record_ids(records)
      records.group_by { |record| record["id"] }.each do |id, matches|
        next if id.nil? || matches.one?

        errors << "Release-impact id #{id.inspect} is duplicated across: #{matches.map { |record| record["__path__"] }.join(", ")}."
      end
    end

    def triggered_contract_ids(ecosystem)
      contracts = ecosystem.fetch("contracts", {})
      contracts.filter_map do |id, contract|
        patterns = contract.is_a?(Hash) ? Array(contract["owned_paths"]) : []
        id if changed_files.any? { |path| patterns.any? { |pattern| path_matches?(pattern, path) } }
      end.sort
    end

    def path_matches?(pattern, path)
      File.fnmatch?(pattern.to_s, path, FILE_MATCH_FLAGS)
    end

    def validate_required_records(triggered_contracts, records)
      return if triggered_contracts.empty?
      return if records.any?

      errors << "Release-sensitive changes affect #{triggered_contracts.join(", ")}, but no changed config/release-impact/*.yml record was provided."
    end

    def build_contract_digests(ecosystem)
      repo_root = ecosystem_path.dirname.dirname
      ecosystem.fetch("contracts", {}).to_h do |id, contract|
        [ id, self.class.contract_digest(repo_root: repo_root, paths: contract["source_files"]) ]
      rescue ValidationError => e
        errors.concat(e.errors)
        [ id, nil ]
      end
    end

    def validate_records(ecosystem, triggered_contracts, records, contract_digests)
      contracts = ecosystem.fetch("contracts", {})
      addons = ecosystem.fetch("addons", {})
      decisions = {}

      records.each do |record|
        path = record["__path__"]
        validate_record_shape(record, path)
        record_contracts = Array(record["contracts"])
        unknown_contracts = record_contracts - contracts.keys
        errors << "#{path} references unknown contracts: #{unknown_contracts.join(", ")}." if unknown_contracts.any?
        validate_contract_digests(path, record_contracts, record["contract_sha256"], contract_digests)

        consumers = record["consumers"].is_a?(Hash) ? record["consumers"] : {}
        unknown_consumers = consumers.keys - addons.keys
        errors << "#{path} references unknown consumers: #{unknown_consumers.join(", ")}." if unknown_consumers.any?

        consumers.each do |consumer, decision|
          validate_consumer_decision(path, consumer, decision)
          next unless decision.is_a?(Hash) && ALLOWED_BUMPS.include?(decision["bump"])

          previous = decisions[consumer]
          if previous && previous != decision["bump"]
            errors << "Consumer #{consumer} has conflicting bumps #{previous} and #{decision["bump"]}."
          else
            decisions[consumer] = decision["bump"]
          end
        end
      end

      recorded_contracts = records.flat_map { |record| Array(record["contracts"]) }.uniq
      missing_contracts = triggered_contracts - recorded_contracts
      errors << "Release-impact records omit triggered contracts: #{missing_contracts.join(", ")}." if missing_contracts.any?

      triggered_contracts.each do |contract_id|
        required_consumers = Array(contracts.dig(contract_id, "consumers"))
        missing_consumers = required_consumers - decisions.keys
        next if missing_consumers.empty?

        errors << "Contract #{contract_id} requires explicit decisions for: #{missing_consumers.join(", ")}."
      end

      decisions
    end

    def validate_record_shape(record, path)
      allowed_keys = %w[schema_version id summary backend contracts contract_sha256 consumers __path__]
      unknown_keys = record.keys - allowed_keys
      errors << "#{path} contains unsupported keys: #{unknown_keys.join(", ")}." if unknown_keys.any?
      errors << "#{path} schema_version must be 1." unless record["schema_version"] == 1
      validate_identifier(record["id"], IMPACT_ID_PATTERN, "release-impact id", path)

      summary = record["summary"]
      errors << "#{path} summary must be 8..240 characters." unless summary.is_a?(String) && summary.strip.length.between?(8, 240)

      backend = record["backend"]
      unless backend.is_a?(Hash)
        errors << "#{path} backend must be an object."
      else
        validate_exact_keys(backend, %w[bump compatibility activation], "#{path} backend")
        errors << "#{path} backend bump is invalid." unless ALLOWED_BUMPS.include?(backend["bump"])
        errors << "#{path} backend compatibility is invalid." unless ALLOWED_COMPATIBILITY.include?(backend["compatibility"])
        errors << "#{path} backend activation is invalid." unless ALLOWED_ACTIVATION.include?(backend["activation"])
      end

      contracts = record["contracts"]
      unless contracts.is_a?(Array) && contracts.any? && contracts.uniq == contracts
        errors << "#{path} contracts must be a non-empty unique array."
      end
      Array(contracts).each { |id| validate_identifier(id, CONTRACT_ID_PATTERN, "contract", path) }

      consumers = record["consumers"]
      errors << "#{path} consumers must be a non-empty object." unless consumers.is_a?(Hash) && consumers.any?
    end

    def validate_contract_digests(path, contracts, declared, current)
      unless declared.is_a?(Hash)
        errors << "#{path} contract_sha256 must be an object."
        return
      end

      validate_exact_keys(declared, contracts, "#{path} contract_sha256")
      declared.each do |contract, digest|
        unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
          errors << "#{path} contract_sha256.#{contract} must be a lowercase SHA-256 digest."
          next
        end

        expected = current[contract]
        errors << "#{path} contract_sha256.#{contract} is stale; expected #{expected}." if expected && digest != expected
      end
    end

    def validate_consumer_decision(path, consumer, decision)
      unless decision.is_a?(Hash)
        errors << "#{path} consumer #{consumer} must be an object."
        return
      end

      validate_exact_keys(decision, %w[bump reason], "#{path} consumer #{consumer}")
      errors << "#{path} consumer #{consumer} bump is invalid." unless ALLOWED_BUMPS.include?(decision["bump"])
      reason = decision["reason"]
      errors << "#{path} consumer #{consumer} reason must be 12..500 characters." unless reason.is_a?(String) && reason.strip.length.between?(12, 500)
    end

    def validate_exact_keys(value, required_keys, label)
      missing = required_keys - value.keys
      extra = value.keys - required_keys
      errors << "#{label} is missing: #{missing.join(", ")}." if missing.any?
      errors << "#{label} contains unsupported keys: #{extra.join(", ")}." if extra.any?
    end

    def validate_identifier(value, pattern, label, path = nil)
      return if value.is_a?(String) && value.match?(pattern)

      prefix = path ? "#{path} " : ""
      errors << "#{prefix}#{label} #{value.inspect} is invalid."
    end

    def validate_public_metadata(value, label, path = [])
      case value
      when Hash
        value.each do |key, nested|
          key_identity = key.to_s.downcase.gsub(/[^a-z0-9_]/, "")
          errors << "#{label} contains forbidden sensitive key #{([ *path, key ]).join(".")}." if SENSITIVE_KEYS.include?(key_identity)
          validate_public_metadata(nested, label, [ *path, key ])
        end
      when Array
        value.each_with_index { |nested, index| validate_public_metadata(nested, label, [ *path, index ]) }
      when String
        NON_PUBLIC_VALUE_PATTERNS.each do |description, pattern|
          errors << "#{label} contains #{description} at #{path.join(".")}." if value.match?(pattern)
        end
      end
    end

    def blank?(value)
      !value.is_a?(String) || value.strip.empty?
    end
  end
end
