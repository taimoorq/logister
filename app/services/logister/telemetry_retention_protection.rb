# frozen_string_literal: true

module Logister
  # Keeps the PostgreSQL replay source available until every derived delivery
  # has completed. The correlated lookup is backed by
  # idx_telemetry_outbox_record and idx_telemetry_deliveries_intent.
  class TelemetryRetentionProtection
    SOURCE_CONFIG = {
      "IngestEvent" => { timestamp_column: "occurred_at" },
      "TraceSpan" => { timestamp_column: "started_at" }
    }.freeze

    class << self
      def without_incomplete_deliveries(relation)
        relation.where(incomplete_delivery_exists(relation).not)
      end

      def with_incomplete_deliveries(relation)
        relation.where(incomplete_delivery_exists(relation))
      end

      private

      def incomplete_delivery_exists(relation)
        model = relation.klass.base_class
        config = SOURCE_CONFIG.fetch(model.name) do
          raise ArgumentError, "Unsupported retention source model: #{model.name}"
        end
        source = model.arel_table
        outbox = TelemetryOutboxEvent.arel_table.alias("retention_outbox")
        delivery = TelemetryDelivery.arel_table.alias("retention_delivery")
        incomplete_delivery = Arel::SelectManager.new(delivery)
          .project(Arel.sql("1"))
          .where(delivery[:telemetry_outbox_event_id].eq(outbox[:id]))
          .where(delivery[:status].not_eq(TelemetryDelivery.statuses.fetch("completed")))
          .exists

        Arel::SelectManager.new(outbox)
          .project(Arel.sql("1"))
          .where(outbox[:project_id].eq(source[:project_id]))
          .where(outbox[:record_type].eq(model.name))
          .where(outbox[:record_id].eq(source[:id]))
          .where(outbox[:recorded_at].eq(source[config.fetch(:timestamp_column)]))
          .where(incomplete_delivery)
          .exists
      end
    end
  end
end
