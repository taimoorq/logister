# frozen_string_literal: true

require "digest"
require "set"
require "uri"

class TelemetryStoreGeneration < ApplicationRecord
  STORE_KINDS = %w[clickhouse].freeze

  validates :store_kind, inclusion: { in: STORE_KINDS }
  validates :generation_id, :first_seen_at, :last_seen_at, presence: true
  validates :generation_id, uniqueness: { scope: :store_kind }
  validate :generation_matches_locator

  class << self
    def clickhouse_locator(config = Rails.configuration.x.logister)
      uri = URI.parse(config.clickhouse_url.to_s)
      uri.user = nil
      uri.password = nil
      uri.query = nil
      uri.fragment = nil
      payload = {
        "url" => uri.to_s,
        "database" => config.clickhouse_database.to_s,
        "events_table" => config.clickhouse_events_table.to_s,
        "spans_table" => config.clickhouse_spans_table.to_s,
        "username" => config.clickhouse_username.to_s
      }
      payload.merge("generation_id" => generation_id_for(payload))
    end

    def register_clickhouse!(config = Rails.configuration.x.logister, now: Time.current)
      return if clickhouse_mode(config) == "disabled"

      locator = clickhouse_locator(config)
      register_locator!(locator, now: now)
    end

    def register_locator!(locator, now: Time.current)
      locator = locator.stringify_keys
      locator["generation_id"] ||= generation_id_for(locator)
      generation = find_or_create_by!(store_kind: "clickhouse", generation_id: locator.fetch("generation_id")) do |row|
        row.locator = locator
        row.first_seen_at = now
        row.last_seen_at = now
      end
      generation.update_columns(last_seen_at: now, updated_at: now) if generation.last_seen_at < now - 1.hour
      generation
    end

    def register_clickhouse_once!(config = Rails.configuration.x.logister)
      generation_id = clickhouse_locator(config).fetch("generation_id")
      return if registered_generation_ids.include?(generation_id)

      registration_mutex.synchronize do
        return if registered_generation_ids.include?(generation_id)

        register_clickhouse!(config)
        registered_generation_ids << generation_id
      end
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => error
      Rails.logger.warn("clickhouse.generation_registry_unavailable error=#{error.class}: #{error.message}")
    end

    def generation_id_for(locator)
      Digest::SHA256.hexdigest(locator.stringify_keys.except("generation_id").sort.to_h.to_json)
    end

    private

    def clickhouse_mode(config)
      configured = config.clickhouse_mode if config.respond_to?(:clickhouse_mode)
      return configured.to_s if configured.present?

      config.respond_to?(:clickhouse_enabled) && config.clickhouse_enabled ? "dual_write" : "disabled"
    end

    def registered_generation_ids
      @registered_generation_ids ||= Set.new
    end

    def registration_mutex
      @registration_mutex ||= Mutex.new
    end
  end

  private

  def generation_matches_locator
    return if locator.is_a?(Hash) && generation_id == self.class.generation_id_for(locator)

    errors.add(:generation_id, "must match the immutable store locator")
  end
end
