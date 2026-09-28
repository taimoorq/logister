# frozen_string_literal: true

# Only explicitly selected, bounded metadata may cross the project boundary.
class ProjectCorrelationSummary
  def initialize
    @deployments = {}
  end

  def prepare(project, rows)
    keys = rows.filter_map { |row| [ project.id, row["environment"].presence || "production", row["release"] ] if row["release"].present? }.uniq
    keys.each { |key| @deployments[key] = [] }
    return if keys.empty?

    deployments = project.deployments.where(environment: keys.map(&:second).uniq, release: keys.map(&:last).uniq).limit(1001).to_a
    return if deployments.size > 1000

    deployments.each do |deployment|
      key = [ project.id, deployment.environment, deployment.release ]
      @deployments[key] << deployment if @deployments.key?(key)
    end
  end

  def call(row, project, evidence: nil)
    at = row["occurred_at"].is_a?(String) ? Time.zone.parse(row["occurred_at"]) : row["occurred_at"]
    details = ProjectCorrelationRecords::CONTEXT_FIELDS.keys.to_h { |key| [ key.to_sym, row[key].to_s.truncate(100).presence ] }
    details[:http_status_code] = Integer(details[:http_status_code], exception: false)&.then { |code| code if code.between?(100, 599) }
    details[:attempt] = Integer(details[:attempt], exception: false)&.then { |attempt| attempt if attempt.between?(1, 1000) }
    duration = Float(row["duration_ms"], exception: false)
    {
      project_uuid: project.uuid, project_name: project.name.truncate(100), integration: project.integration_kind,
      uuid: row["uuid"], type: row["type"], occurred_at: at.utc.iso8601(6), evidence:,
      **%w[trace_id span_id parent_span_id request_id].to_h { |key| [ key.to_sym, row[key].presence ] },
      environment: row["environment"].presence || "production", release: row["release"].presence,
      operation: row["operation"].to_s.split(/[?#]/).first.presence,
      duration_ms: duration&.finite? && duration >= 0 ? duration.round(2) : nil,
      status: row["status"].to_s.presence_in(%w[ok error unset]), kind: row["kind"].presence,
      deployment: deployment(project, row, at), **details
    }.compact
  end

  def enrich_issues!(items, project:, from:, to:)
    errors = items.select { |item| item[:type] == "error" }
    return if errors.empty?

    events = project.ingest_events.where(uuid: errors.pluck(:uuid), occurred_at: from...to)
      .select(:id, :uuid, :occurred_at, :error_group_id).includes(error_group: :assignee).index_by(&:uuid)
    errors.each do |item|
      group = events[item[:uuid]]&.error_group
      next unless group

      item[:issue] = { uuid: group.uuid, title: group.title.to_s.truncate(200), status: group.status,
        assignee: group.assignee&.name.to_s.truncate(200).presence }.compact
    end
  end

  private

  def deployment(project, row, at)
    return if row["release"].blank?

    key = [ project.id, row["environment"].presence || "production", row["release"] ]
    candidates = @deployments[key] ||= project.deployments.where(environment: key[1], release: key[2]).limit(2).to_a
    return unless candidates.one?

    deployment = candidates.first
    return if (deployment.deployed_at || deployment.created_at) > at

    { uuid: deployment.uuid, release: deployment.release, evidence: "exact_release", repository: deployment.repository_full_name,
      deployed_at: (deployment.deployed_at || deployment.created_at).utc.iso8601(6) }
  end
end
