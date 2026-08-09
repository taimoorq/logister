# frozen_string_literal: true

module Logister
  class ClickhouseEventRollup
    EVENT_TYPES = %w[error log metric transaction check_in].freeze

    class << self
      def call(project_ids:, since:, to: Time.current, client:)
        new(project_ids:, since:, to:, client:).call
      end
    end

    def initialize(project_ids:, since:, to:, client:)
      @project_ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq
      @since = since
      @to = to
      @client = client
    end

    def call
      return empty_rollup if @project_ids.empty?

      rows = @client.select_rows!(query)
      build_rollup(rows)
    end

    private

    def query
      <<~SQL.squish
        SELECT
          project_id,
          event_type,
          count() AS count,
          max(occurred_at) AS latest_event_at
        FROM #{@client.event_facts_table_name}
        WHERE project_id IN (#{@project_ids.join(", ")})
          AND occurred_at >= parseDateTime64BestEffort(#{quoted_since}, 3)
          AND occurred_at < parseDateTime64BestEffort(#{quoted_to}, 3)
        GROUP BY project_id, event_type
      SQL
    end

    def quoted_since
      "'#{@since.to_time.utc.iso8601(3)}'"
    end

    def quoted_to
      "'#{@to.to_time.utc.iso8601(3)}'"
    end

    def build_rollup(rows)
      rows.each_with_object(empty_rollup) do |row, rollup|
        project_id = row.fetch("project_id").to_i
        event_type = row.fetch("event_type").to_s
        count = row.fetch("count").to_i
        latest_event_at = parse_time(row["latest_event_at"])

        rollup[:event_type_counts][event_type] += count if EVENT_TYPES.include?(event_type)
        rollup[:active_project_ids] << project_id
        rollup[:activity_event_counts][project_id] += count unless event_type == "error"

        current_latest = rollup[:latest_event_at_by_project][project_id]
        if latest_event_at.present? && (current_latest.blank? || latest_event_at > current_latest)
          rollup[:latest_event_at_by_project][project_id] = latest_event_at
        end
      end.tap do |rollup|
        rollup[:active_project_ids].uniq!
      end
    end

    def empty_rollup
      {
        event_type_counts: EVENT_TYPES.index_with { 0 },
        active_project_ids: [],
        activity_event_counts: Hash.new(0),
        latest_event_at_by_project: {}
      }
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)&.utc
    rescue ArgumentError
      nil
    end
  end
end
