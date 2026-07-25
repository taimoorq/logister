# frozen_string_literal: true

module Logister
  class ClickhouseEventBackfill
    DEFAULT_BATCH_SIZE = 250

    def initialize(scope:, client: ClickhouseClient.new, batch_size: DEFAULT_BATCH_SIZE)
      @scope = scope
      @client = client
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
    end

    def call
      return 0 unless @client.enabled?

      inserted = 0
      @scope.in_batches(of: @batch_size) do |batch|
        events = batch.includes(:project).to_a
        rows = events.map do |event|
          EventIngestor.new(event:, request_context: {}).attributes
        end
        existing_ids = existing_event_ids(rows.map { |row| row.fetch(:event_id) })
        rows.reject! { |row| existing_ids.include?(row.fetch(:event_id).to_s) }
        next if rows.empty?

        @client.insert_events!(rows)
        inserted += rows.size
      end
      inserted
    end

    private

    def existing_event_ids(event_ids)
      return [] if event_ids.empty?

      values = event_ids.map { |event_id| "'#{event_id.to_s.gsub("'", "\\\\'")}'" }.join(", ")
      @client.select_rows!(<<~SQL.squish).map { |row| row.fetch("event_id").to_s }
        SELECT toString(event_id) AS event_id
        FROM #{@client.events_table_name}
        WHERE event_id IN (#{values})
      SQL
    end
  end
end
