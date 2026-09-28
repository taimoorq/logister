# frozen_string_literal: true

# A bounded occurrence lookup. A project link never grants read permission.
class ProjectCorrelationsQuery
  LIMIT = 500
  BYTES_LIMIT = 1.megabyte
  SIGNALS = ProjectCorrelationRecords::SIGNALS
  class InvalidRange < StandardError; end

  def self.call(...) = new(...).call

  def initialize(principal:, project:, event:, from: nil, to: nil)
    @principal, @project, @event = principal, project, event
    @from = parse_time(from) || event.occurred_at - 15.minutes
    @to = parse_time(to) || event.occurred_at + 15.minutes
    raise InvalidRange, "Choose a time range of up to 24 hours." unless @to > @from && @to - @from <= 24.hours
    @ids = CorrelationContext.new(event.context)
  end

  def call
    scope = ProjectCorrelationPolicy.projects(principal: @principal, anchor: @project, environment: IngestEvent.environment(@event))
    result = { items: [], coverage: [], from: @from.iso8601(3), to: @to.iso8601(3), truncated: false, partial: false }
    evidence = TelemetryEvidence.for(@event)
    if evidence.reporting_interval? || evidence.received_only? || (@ids.conflicts & %w[trace_id request_id]).any? || (@ids.matchable("trace_id").blank? && @ids.matchable("request_id").blank?)
      return result.merge(reason: "This occurrence has no unambiguous request identifiers.")
    end

    projects = @principal.accessible_projects.where(id: scope.keys).index_by(&:id)
    summary = ProjectCorrelationSummary.new
    scope.each do |id, environments|
      project = projects.fetch(id)
      read = reader.call(project:, environments:)
      summary.prepare(project, read[:rows])
      result[:coverage].concat(read[:coverage])
      result[:truncated] ||= read[:truncated]
      items = read[:rows].filter_map do |row|
        match = ProjectCorrelationMatch.evidence(@ids, CorrelationContext.new(row))
        summary.call(row, project, evidence: match) if match
      end
      summary.enrich_issues!(items, project:, from: @from, to: @to)
      result[:items].concat(items)
    end
    # Re-resolve membership and links after metadata reads; no cached authorization.
    fresh = ProjectCorrelationPolicy.projects(principal: @principal, anchor: @project, environment: IngestEvent.environment(@event))
    visible = projects.values.select { |p| fresh.key?(p.id) }.to_h { |p| [ p.uuid, fresh[p.id] ] }
    result[:coverage].select! { |row| visible.include?(row[:project_uuid]) }
    items = result[:items].select { |row| visible.fetch(row[:project_uuid], []).include?(row[:environment]) }
      .sort_by { |row| [ row[:occurred_at], row[:project_uuid], row[:uuid] ] }
    result[:anchor] = items.find { |row| row[:project_uuid] == @project.uuid && row[:uuid] == @event.uuid }
    items.reject! { |row| row[:project_uuid] == @project.uuid && row[:uuid] == @event.uuid }
    result[:truncated] ||= items.size > LIMIT
    bytes = JSON.generate(result.except(:items)).bytesize
    result[:items] = items.first(LIMIT).take_while do |item|
      bytes += JSON.generate(item).bytesize + 1
      bytes < BYTES_LIMIT
    end
    result[:truncated] ||= result[:items].size < items.size
    result[:partial] = result[:truncated] || result[:coverage].any? { |row| row[:partial] }
    result
  end

  private

  def parse_time(value)
    Time.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    raise InvalidRange, "Use an ISO 8601 timestamp."
  end

  def reader
    @reader ||= ProjectCorrelationRecords.new(from: @from, to: @to, identities: [ @ids ], limit: LIMIT)
  end

  # Retain private storage probes used by the actual-store parity specification.
  def postgres_rows(...) = reader.send(:postgres_rows, ...)
  def clickhouse_rows(...) = reader.send(:clickhouse_rows, ...)
  def quote(...) = reader.send(:quote, ...)
end
