# frozen_string_literal: true

module Logister
  class RuntimeReleaseIdentity
    IMAGE_DIGEST_PATTERN = /\Asha256:[0-9a-f]{64}\z/
    FEATURE_FLAGS = %w[
      LOGISTER_CLI_FEATURE_TRACES
      LOGISTER_CLI_FEATURE_MONITORS
      LOGISTER_CLI_FEATURE_DEPLOYMENTS
      LOGISTER_CLI_FEATURE_INSIGHTS
      LOGISTER_CLI_FEATURE_METRICS
    ].freeze

    class << self
      def call
        new.call
      end
    end

    def initialize(env: ENV, migration_check: -> { ActiveRecord::Migration.check_all_pending! })
      @env = env
      @migration_check = migration_check
    end

    def call
      identity = ReleaseIdentity.new(repo_root: Rails.root).validate!
      errors = []
      configured_version = env["LOGISTER_RELEASE"].to_s.strip
      git_sha = env["LOGISTER_GIT_SHA"].to_s.strip
      image_digest = env["LOGISTER_IMAGE_DIGEST"].to_s.strip

      errors << "configured release does not match the packaged version" if configured_version.present? && configured_version.delete_prefix("v") != identity.version
      errors << "release Git revision is invalid" if git_sha.present? && git_sha != "unknown" && !git_sha.match?(ReleaseIdentity::GIT_SHA_PATTERN)
      errors << "release image digest is invalid" if image_digest.present? && !image_digest.match?(IMAGE_DIGEST_PATTERN)

      database = database_status(errors)
      payload = {
        schema_version: 1,
        status: errors.empty? ? "ok" : "degraded",
        version: identity.version,
        tag: identity.tag,
        git_sha: git_sha.presence || "unknown",
        image_digest: image_digest.presence || "unknown",
        contract_sha256: identity.contract_sha256,
        database: database,
        feature_flags: FEATURE_FLAGS.to_h { |name| [ name, truthy?(env[name]) ] },
        errors: errors
      }

      payload
    rescue ReleaseIdentity::ValidationError
      {
        schema_version: 1,
        status: "degraded",
        version: "unknown",
        tag: "unknown",
        git_sha: "unknown",
        image_digest: "unknown",
        contract_sha256: {},
        database: { connected: false, migrations_current: false },
        feature_flags: FEATURE_FLAGS.to_h { |name| [ name, truthy?(env[name]) ] },
        errors: [ "packaged release identity is invalid" ]
      }
    end

    private

    attr_reader :env, :migration_check

    def database_status(errors)
      connected = ActiveRecord::Base.connection.active?
      errors << "database connection is unavailable" unless connected
      migrations_current = false
      if connected
        migration_check.call
        migrations_current = true
      end

      { connected: connected, migrations_current: migrations_current }
    rescue ActiveRecord::PendingMigrationError
      errors << "database migrations are pending"
      { connected: true, migrations_current: false }
    rescue ActiveRecord::ActiveRecordError
      errors << "database verification failed"
      { connected: false, migrations_current: false }
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end
  end
end
