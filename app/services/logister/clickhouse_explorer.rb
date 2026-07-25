# frozen_string_literal: true

module Logister
  class ClickhouseExplorer
    EVENT_TYPES = %w[error log metric transaction check_in].freeze

    class << self
      def call(project_ids:, since:, event_type: nil, environment: nil, occurred_on: nil,
               environment_limit:, client: ClickhouseClient.new)
        new(
          project_ids:,
          since:,
          event_type:,
          environment:,
          occurred_on:,
          environment_limit:,
          client:
        ).call
      end
    end

    def initialize(project_ids:, since:, event_type:, environment:, occurred_on:, environment_limit:, client:)
      @project_ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq
      @since = since
      @event_type = event_type.to_s.presence
      @environment = environment.to_s.presence
      @occurred_on = occurred_on
      @environment_limit = environment_limit.to_i
      @client = client
    end

    def call
      return unless @client.read_enabled?
      return empty_payload if @project_ids.empty?

      build_payload(@client.select_rows!(query))
    rescue StandardError => error
      Rails.logger.warn("clickhouse dashboard explorer failed: #{error.class} #{error.message}")
      nil
    end

    private

    def query
      <<~SQL.squish
        SELECT
          toDate(occurred_at) AS day,
          project_id,
          event_type,
          #{environment_expression} AS environment_name,
          uniqExact(event_id) AS count
        FROM #{@client.events_table_name}
        WHERE #{query_filters.join(" AND ")}
        GROUP BY day, project_id, event_type, environment_name
      SQL
    end

    def query_filters
      filters = [
        "project_id IN (#{@project_ids.join(", ")})",
        "occurred_at >= parseDateTime64BestEffort(#{quote(@since.to_time.utc.iso8601(3))}, 3)"
      ]
      filters << "event_type = #{quote(@event_type)}" if @event_type
      filters << "#{environment_expression} = #{quote(@environment)}" if @environment
      if @occurred_on
        day_start = @occurred_on.in_time_zone.beginning_of_day.utc
        filters << "occurred_at >= parseDateTime64BestEffort(#{quote(day_start.iso8601(3))}, 3)"
        filters << "occurred_at < parseDateTime64BestEffort(#{quote((day_start + 1.day).iso8601(3))}, 3)"
      end
      filters
    end

    def environment_expression
      "if(empty(environment), 'unknown', environment)"
    end

    def quote(value)
      escaped = value.to_s.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
      "'#{escaped}'"
    end

    def build_payload(rows)
      event_type_counts = EVENT_TYPES.index_with { 0 }
      timeline_counts = Hash.new(0)
      project_counts = Hash.new(0)
      environment_counts = Hash.new(0)

      rows.each do |row|
        day = row.fetch("day").to_s
        project_id = row.fetch("project_id").to_i
        event_type = row.fetch("event_type").to_s
        environment = row.fetch("environment_name").to_s.presence || "unknown"
        count = row.fetch("count").to_i

        event_type_counts[event_type] += count if EVENT_TYPES.include?(event_type)
        timeline_counts[[ day, event_type ]] += count
        project_counts[project_id] += count
        environment_counts[environment] += count
      end

      {
        totals: {
          events: project_counts.values.sum,
          active_projects: project_counts.size,
          environments: environment_counts.size
        },
        timeline: timeline_counts.map do |(day, event_type), count|
          { day:, event_type:, count: }
        end.sort_by { |row| [ row[:day], row[:event_type] ] },
        event_types: event_type_counts,
        projects: project_counts.map do |project_id, count|
          { project_id:, count: }
        end.sort_by { |row| [ -row[:count], row[:project_id] ] },
        environments: environment_counts.map do |name, count|
          { name:, count: }
        end.sort_by { |row| [ -row[:count], row[:name] ] }.first(@environment_limit)
      }
    end

    def empty_payload
      {
        totals: { events: 0, active_projects: 0, environments: 0 },
        timeline: [],
        event_types: EVENT_TYPES.index_with { 0 },
        projects: [],
        environments: []
      }
    end
  end
end
