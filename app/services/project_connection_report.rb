# frozen_string_literal: true

# Batches candidate reads by project, never by occurrence. Counts describe the
# bounded observed population; a partial sample cannot prove absence or recovery.
class ProjectConnectionReport
  LIMIT = 500
  PAIR_LIMIT = 2000
  SIGNALS = %w[error transaction span].freeze
  class InvalidScope < StandardError; end

  def initialize(principal:, project:, params: {}, now: Time.current, group_uuids: nil)
    @principal, @project = principal, project
    @params = params.to_h.symbolize_keys
    @group_uuids = group_uuids
    raise InvalidScope, "Inspect up to 100 issues at a time." if group_uuids && group_uuids.size > 100
    raise InvalidScope, "Filter values must be no longer than 200 characters." if @params.values.any? { |value| value.to_s.length > 200 }
    @deployment = @project.deployments.find_by!(uuid: @params[:deployment_uuid]) if @params[:deployment_uuid].present?
    @deployed_at = @deployment && (@deployment.deployed_at || @deployment.created_at)
    @to = time(@params[:to]) || (@deployed_at ? [ @deployed_at + 12.hours, now ].min : now)
    @from = time(@params[:from]) || (@deployed_at ? @deployed_at - 12.hours : @to - 24.hours)
    raise InvalidScope, "Choose a window of up to seven days." unless @to > @from && @to - @from <= 7.days
    @environment = @deployment&.environment || @params[:environment].to_s.presence || "production"
    @summary = ProjectCorrelationSummary.new
    @coverage, @truncated, @pairs, @pair_bytes = [], false, [], 0
  end

  def call
    Logister::CliPostgresStatementTimeout.call { build }
  end

  private

  def build
    scope = authorized_scope
    projects = @principal.accessible_projects.where(id: scope.keys).index_by(&:id)
    own_reader = ProjectCorrelationRecords.new(from: @from, to: @to, filters: anchor_filters, newest_first: true)
    anchors = records(own_reader, @project, scope.fetch(@project.id))
      .sort_by { |row| row[:occurred_at] }.reverse
    @truncated ||= anchors.size > LIMIT
    anchors = anchors.first(LIMIT)
    identities = anchors.map { |row| CorrelationContext.new(row.stringify_keys) }
    peers = []
    unless identities.empty?
      peer_filters = @params.slice(:peer_release, :peer_app_version, :peer_build_number).compact_blank.transform_keys { |key| key.to_s.delete_prefix("peer_").to_sym }
      reader = ProjectCorrelationRecords.new(from: @from, to: @to, identities:, filters: peer_filters, newest_first: true)
      scope.except(@project.id).each do |id, environments|
        rows = records(reader, projects.fetch(id), environments)
        peers.concat(rows)
      end
    end
    # Recheck links and membership before deriving names, counts, dimensions or pairs.
    fresh = authorized_scope
    visible = projects.values.select { |project| fresh.key?(project.id) }.to_h { |project| [ project.uuid, fresh[project.id] ] }
    peers.select! { |row| visible.fetch(row[:project_uuid], []).include?(row[:environment]) }
    @coverage.select! { |row| visible.key?(row[:project_uuid]) }
    index = candidate_index(peers)
    anchors.each do |anchor|
      ids = CorrelationContext.new(anchor.stringify_keys)
      candidates = [ *index[[ :trace_id, anchor[:trace_id] ]], *index[[ :request_id, anchor[:request_id] ]] ].uniq
      candidates.each do |peer|
        next if (Time.iso8601(anchor[:occurred_at]) - Time.iso8601(peer[:occurred_at])).abs > 15.minutes
        match = ProjectCorrelationMatch.evidence(ids, CorrelationContext.new(peer.stringify_keys))
        next unless match
        next if @params[:only_errors] == "1" && anchor[:type] != "error" && peer[:type] != "error"
        pair = { anchor:, peer:, evidence: match }
        bytes = pair.to_json.bytesize
        if @pairs.size >= PAIR_LIMIT || @pair_bytes + bytes > 550.kilobytes
          @truncated = true
          break
        end
        @pairs << pair
        @pair_bytes += bytes
      end
    end
    connected_rows = @pairs.flat_map { |pair| [ pair[:anchor], pair[:peer] ] }.uniq { |row| key(row) }
    # Impact reads are batched per mobile project and contain counts only.
    impact = impact_for(connected_rows, projects)
    final_scope = authorized_scope
    if final_scope != fresh
      # Counts computed against revoked scope must not survive even if no row is displayed.
      raise ActiveRecord::RecordNotFound
    end
    metrics = metrics_for(anchors, connected_rows)
    @truncated ||= metrics.size > 200
    {
      from: @from.iso8601(6), to: @to.iso8601(6), environment: @environment,
      anchor_count: anchors.size, matched_anchor_count: @pairs.map { |pair| key(pair[:anchor]) }.uniq.size,
      pairs: @pairs, metrics: metrics.first(200), impact:, comparison: comparison_for(connected_rows),
      coverage: @coverage, truncated: @truncated,
      partial: @truncated || @coverage.any? { |row| row[:partial] },
      peers: projects.values.reject { |project| project.id == @project.id || !final_scope.key?(project.id) }.map { |project| { uuid: project.uuid, name: project.name, environments: final_scope[project.id] } },
      limit: LIMIT, pair_limit: PAIR_LIMIT
    }
  end

  def authorized_scope
    scope = ProjectCorrelationPolicy.projects(principal: @principal, anchor: @project, environment: @environment)
    if @params[:connected_project].present?
      peer = @principal.accessible_projects.find_by!(uuid: @params[:connected_project])
      raise ActiveRecord::RecordNotFound unless peer.id != @project.id && scope.key?(peer.id)
      scope.slice(@project.id, peer.id)
    else
      scope
    end
  end

  def anchor_filters
    filters = @params.slice(:release, :build_number, :app_version).compact_blank
    if @params[:group_uuid].present? || @group_uuids
      group_ids = if @group_uuids
        @project.error_groups.where(uuid: @group_uuids).select(:id)
      else
        @project.error_groups.find_by!(uuid: @params[:group_uuid]).id
      end
      uuids = @project.ingest_events.where(error_group_id: group_ids, occurred_at: @from...@to)
        .order(occurred_at: :desc).limit(LIMIT + 1).pluck(:uuid)
      @truncated ||= uuids.size > LIMIT
      filters[:event_uuids] = uuids.first(LIMIT)
    end
    filters
  end

  def records(reader, project, environments)
    read = reader.call(project:, environments:, signals: SIGNALS)
    @coverage.concat(read[:coverage])
    @truncated ||= read[:truncated]
    @summary.prepare(project, read[:rows])
    items = read[:rows].map { |row| @summary.call(row, project) }
    @summary.enrich_issues!(items, project:, from: @from, to: @to)
    items
  end

  def candidate_index(rows)
    rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |row, index|
      %i[trace_id request_id].each { |field| index[[ field, row[field] ]] << row if row[field].present? }
    end
  end

  def metrics_for(anchors, matched)
    # The anchor population includes unmatched requests so the match count is interpretable.
    (anchors + matched).uniq { |row| key(row) }.group_by { |row| [ row[:project_uuid], row[:operation], row[:release], row[:app_version], row[:build_number], row[:duration_scope], row[:kind] ] }.map do |_, rows|
      requests = rows.select { |row| row[:type] == "span" && %w[http server browser].include?(row[:kind]) }
      known = requests.select { |row| row[:status].in?(%w[ok error]) || row[:http_status_code] }
      durations = requests.filter_map { |row| row[:duration_ms] }.sort
      errors = rows.select { |row| row[:type] == "error" }
      rows.first.slice(:project_uuid, :project_name, :operation, :release, :app_version, :build_number, :duration_scope).merge(
        requests: requests.size, known_outcomes: known.size,
        failed_requests: known.count { |row| row[:status] == "error" || row[:http_status_code].to_i >= 400 },
        p95_ms: durations.empty? ? nil : durations[((durations.size - 1) * 0.95).ceil], duration_count: durations.size,
        errors: errors.size, issues: errors.filter_map { |row| row.dig(:issue, :uuid) }.uniq.size,
        example: rows.first.slice(:project_uuid, :uuid, :type, :occurred_at, :environment)
      )
    end.sort_by { |row| [ -row[:errors], -row[:failed_requests], row[:project_name].to_s, row[:operation].to_s ] }
  end

  def impact_for(rows, projects)
    rows.select { |row| row[:type] == "error" }.group_by { |row| row[:project_uuid] }.filter_map do |uuid, errors|
      project = projects.values.find { |candidate| candidate.uuid == uuid }
      next unless project && (project.integration_android? || project.integration_ios?)
      scope = ErrorOccurrence.joins("INNER JOIN ingest_events ON ingest_events.id = error_occurrences.ingest_event_id AND ingest_events.occurred_at = error_occurrences.ingest_event_occurred_at")
        .where(ingest_events: { project_id: project.id, uuid: errors.pluck(:uuid), occurred_at: @from...@to })
      total, installation_observations, installations, session_observations, sessions = scope.pick(Arel.sql("COUNT(*), COUNT(installation_hash), COUNT(DISTINCT installation_hash), COUNT(session_hash), COUNT(DISTINCT session_hash)"))
      { project_uuid: uuid, project_name: project.name, matched_errors: errors.size,
        retained_occurrences: total.to_i, installation_observations: installation_observations.to_i,
        installations: installation_observations.to_i.positive? ? installations.to_i : nil,
        session_observations: session_observations.to_i, sessions: session_observations.to_i.positive? ? sessions.to_i : nil }
    end
  end

  def key(row) = [ row[:project_uuid], row[:type], row[:uuid] ]

  def comparison_for(rows)
    return unless @deployment

    { release: @deployment.release, deployed_at: @deployed_at.iso8601(6),
      before_seconds: [ [ @deployed_at, @to ].min - @from, 0 ].max, after_seconds: [ @to - [ @deployed_at, @from ].max, 0 ].max,
      projects: rows.group_by { |row| row[:project_uuid] }.map do |_, records|
        errors = records.select { |row| row[:type] == "error" }
        { project_name: records.first[:project_name],
          before_errors: errors.count { |row| Time.iso8601(row[:occurred_at]) < @deployed_at },
          after_errors: errors.count { |row| Time.iso8601(row[:occurred_at]) >= @deployed_at } }
      end }
  end

  def time(value)
    Time.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    raise InvalidScope, "Use an ISO 8601 timestamp."
  end
end
