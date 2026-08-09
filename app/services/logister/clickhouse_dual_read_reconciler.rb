# frozen_string_literal: true

require "digest"
require "json"

module Logister
  class ClickhouseDualReadReconciler
    Result = Data.define(:compared, :equivalent, :primary_digest, :shadow_digest, :error) do
      def compared?
        compared
      end

      def to_h
        {
          compared: compared?,
          equivalent: equivalent,
          primary_digest: primary_digest,
          shadow_digest: shadow_digest,
          error: error
        }.compact
      end
    end

    def initialize(sample_rate: ENV.fetch("LOGISTER_CLICKHOUSE_DUAL_READ_SAMPLE_RATE", "0.01").to_f, logger: Rails.logger)
      @sample_rate = sample_rate.clamp(0.0, 1.0)
      @logger = logger
    end

    def sampled?(sample_key)
      return false if @sample_rate.zero?
      return true if @sample_rate == 1.0

      Digest::SHA256.hexdigest(sample_key.to_s).first(8).to_i(16).fdiv(0xffffffff) < @sample_rate
    end

    def compare(primary:, shadow:, context: {})
      primary_digest = digest(primary)
      shadow_digest = digest(shadow)
      equivalent = primary_digest == shadow_digest
      payload = context.merge(equivalent:, primary_digest:, shadow_digest:)
      ActiveSupport::Notifications.instrument("clickhouse.dual_read.logister", payload)
      @logger.warn("ClickHouse dual-read mismatch #{payload.to_json}") unless equivalent
      Result.new(true, equivalent, primary_digest, shadow_digest, nil)
    rescue StandardError => error
      @logger.warn("ClickHouse dual-read comparison failed: #{error.class} #{error.message}")
      Result.new(false, nil, nil, nil, "#{error.class}: #{error.message}")
    end

    def skipped
      Result.new(false, nil, nil, nil, nil)
    end

    private

    def digest(payload)
      Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
    end

    def canonical(value)
      case value
      when Hash
        value.stringify_keys.except("analytics", "generated_at").sort.to_h.transform_values { |item| canonical(item) }
      when Array
        value.map { |item| canonical(item) }
      when Time, DateTime
        value.utc.iso8601(6)
      when BigDecimal
        value.to_f.round(6)
      when Float
        value.round(6)
      else
        value
      end
    end
  end
end
