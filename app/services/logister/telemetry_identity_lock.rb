# frozen_string_literal: true

require "digest"

module Logister
  class TelemetryIdentityLock
    def self.acquire!(project_id:, client_identifiers:, connection: ActiveRecord::Base.connection)
      return unless connection.adapter_name.downcase.include?("postgresql")

      lock_keys = Array(client_identifiers).filter_map do |identifier|
        normalized = TelemetryIdentity.normalize_uuid(identifier)
        next unless normalized

        Digest::SHA256.digest("logister:telemetry:#{project_id}:#{normalized}").unpack1("q>")
      end.uniq.sort
      return if lock_keys.empty?

      values = lock_keys.map { |key| "(#{key})" }.join(", ")
      connection.execute(<<~SQL.squish)
        SELECT pg_advisory_xact_lock(ordered_locks.lock_key)
        FROM (
          SELECT lock_key
          FROM (VALUES #{values}) AS identity_locks(lock_key)
          ORDER BY lock_key
        ) ordered_locks
      SQL
    end
  end
end
