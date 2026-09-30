# frozen_string_literal: true

# One INSERT for specs where the number of events is the point (windows, batches,
# thresholds). A factory per row costs a few milliseconds each, and every event
# built by default also builds its own API key. Use factories when a spec cares
# about a handful of records and what is on them.
module BulkRecords
  # Inserts one event per time, oldest to newest as given, and returns their ids
  # in the same order. `context` may be a hash or a callable that receives the time.
  def insert_events(project:, api_key:, times:, event_type: :error, level: "error", context: {})
    rows = times.each_with_index.map do |occurred_at, index|
      {
        project_id: project.id,
        api_key_id: api_key.id,
        event_type: IngestEvent.event_types.fetch(event_type.to_s),
        level: level,
        message: "Bulk #{event_type} #{index}",
        context: context.respond_to?(:call) ? context.call(occurred_at) : context,
        occurred_at: occurred_at
      }
    end
    IngestEvent.insert_all!(rows, returning: %w[id]).rows.flatten
  end
end

RSpec.configure { |config| config.include BulkRecords }
