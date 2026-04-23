module IngestEventReporting
  extend ActiveSupport::Concern

  class_methods do
    def released_error_groups(project, lookback: 30.days, limit: 6)
      since = lookback.is_a?(ActiveSupport::Duration) ? lookback.ago : lookback
      release_sql = Arel.sql("context->>'release'")
      releases = released.where(project: project)
                         .where("occurred_at >= ?", since)
                         .group(release_sql)
                         .maximum(:occurred_at)
                         .sort_by { |_rel, seen_at| seen_at || Time.zone.at(0) }
                         .reverse
                         .first(limit)
      return [] if releases.empty?

      release_names = releases.map(&:first)
      events_scope = where(project: project).where("context->>'release' IN (?)", release_names)
      total_events_by_release = grouped_count(events_scope, release_sql)
      error_events_by_release = grouped_count(events_scope.where(event_type: event_types[:error]), release_sql)
      introduced_issues_by_release = grouped_count(project.error_groups.where(introduced_in_release: release_names), :introduced_in_release)
      regressed_issues_by_release = grouped_count(project.error_groups.where(regressed_in_release: release_names), :regressed_in_release)

      releases.map do |release_name, last_seen_at|
        {
          release: release_name,
          last_seen_at: last_seen_at,
          total_events: total_events_by_release.fetch(release_name, 0),
          error_events: error_events_by_release.fetch(release_name, 0),
          introduced_issues: introduced_issues_by_release.fetch(release_name, 0),
          regressed_issues: regressed_issues_by_release.fetch(release_name, 0)
        }
      end
    end

    def transaction_stats(project, since: 24.hours.ago, apdex_threshold_ms: 300.0)
      events = recent_transactions(since, 2000).where(project: project).to_a
      return { count: 0, throughput_per_minute: 0.0, p50_ms: 0.0, p95_ms: 0.0, error_rate: 0.0, apdex: 0.0 } if events.empty?

      durations = events.map { |event| duration_ms(event) }.select(&:positive?).sort
      p50_index = [ (durations.length * 0.50).ceil - 1, 0 ].max
      p95_index = [ (durations.length * 0.95).ceil - 1, 0 ].max
      threshold = apdex_threshold_ms.to_f.positive? ? apdex_threshold_ms.to_f : 300.0

      errored_count = events.count do |event|
        event.level.to_s.in?(%w[error fatal]) || context_value(event, "status").to_i >= 500
      end

      satisfied = events.count { |event| duration_ms(event) <= threshold }
      tolerating = events.count { |event| duration_ms(event) > threshold && duration_ms(event) <= (threshold * 4.0) }
      apdex = ((satisfied + (tolerating * 0.5)) / events.length.to_f).round(3)

      {
        count: events.length,
        throughput_per_minute: (events.length / 1440.0).round(3),
        p50_ms: durations[p50_index].to_f.round(2),
        p95_ms: durations[p95_index].to_f.round(2),
        error_rate: (errored_count / events.length.to_f).round(3),
        apdex: apdex
      }
    end

    def slow_transactions_with_errors(project, since: 24.hours.ago, limit: 20)
      tx_events = recent_transactions(since, 3000).where(project: project).to_a
      return [] if tx_events.empty?

      error_by_tx_name = where(project: project, event_type: :error)
        .where("occurred_at >= ?", since)
        .group_by { |event| transaction_name(event).to_s }

      tx_events
        .sort_by { |event| -duration_ms(event) }
        .first(limit)
        .map do |event|
          name = transaction_name(event).to_s
          related = error_by_tx_name[name] || []
          {
            event: event,
            duration_ms: duration_ms(event).round(2),
            transaction_name: name.presence || "(unnamed transaction)",
            related_error_count: related.length,
            related_error_event: related.max_by(&:occurred_at)
          }
        end
    end

    def related_logs(project:, event:, window: 5.minutes, limit: 50)
      trace = trace_id(event)
      request = request_id(event)
      session = session_id(event)
      user = user_identifier(event)
      return [] if [ trace, request, session, user ].all?(&:blank?)

      start_time = (event.occurred_at || Time.current) - window
      end_time = (event.occurred_at || Time.current) + window

      match_conditions = related_log_match_conditions(
        trace: trace,
        request: request,
        session: session,
        user: user
      )
      return [] if match_conditions.empty?

      sql_fragments = match_conditions.map { |condition| "(#{condition[:sql]})" }.join(" OR ")
      bind_values = match_conditions.flat_map { |condition| condition[:values] }

      logs.where(project: project, occurred_at: start_time..end_time)
          .where([ sql_fragments, *bind_values ])
          .order(occurred_at: :desc)
          .limit(limit)
          .to_a
    end

    def db_stats_from_events(events)
      durations = events.map { |e| duration_ms(e) }.select(&:positive?)
      return { count: 0, avg_ms: 0.0, p95_ms: 0.0 } if durations.empty?

      sorted = durations.sort
      p95_index = [ (sorted.length * 0.95).ceil - 1, 0 ].max
      {
        count: durations.length,
        avg_ms: (durations.sum / durations.length).round(2),
        p95_ms: sorted[p95_index].round(2)
      }
    end

    def dashboard_error_views(events)
      grouped = events.group_by do |event|
        [ event.project_id, event.fingerprint.presence || event.message.to_s.lines.first.to_s.strip.presence || event.uuid ]
      end

      project_views = grouped.map do |(_, _fingerprint), grouped_events|
        latest = grouped_events.max_by { |e| e.occurred_at || Time.zone.at(0) }
        project = latest.project
        trend_points = 7.times.map do |index|
          date = Date.current - (6 - index)
          grouped_events.count { |e| e.occurred_at&.to_date == date }
        end
        ctx = latest.context.is_a?(Hash) ? latest.context : {}
        stage = ctx["environment"].presence || ctx[:environment].presence || "production"

        {
          fingerprint: latest.fingerprint.presence || latest.uuid,
          project: project,
          latest_event: latest,
          title: latest.message.to_s.lines.first.to_s.strip.presence || "Untitled error",
          events_count: grouped_events.length,
          trend: trend_points,
          stage: stage
        }
      end

      project_views
        .group_by { |view| view[:project] }
        .map do |project, views|
          sorted_views = views.sort_by { |view| view[:latest_event].occurred_at || Time.zone.at(0) }.reverse

          {
            project: project,
            latest_event: sorted_views.first[:latest_event],
            events_count: sorted_views.sum { |view| view[:events_count] },
            error_views: sorted_views
          }
        end
        .sort_by { |project_view| project_view[:latest_event].occurred_at || Time.zone.at(0) }
        .reverse
        .first(6)
    end

    private

    def grouped_count(relation, field)
      relation.group(field).count(:all)
    end

    def related_log_match_conditions(trace:, request:, session:, user:)
      conditions = []

      if trace.present?
        conditions << {
          sql: "(context->>'trace_id' = ? OR context->>'traceId' = ? OR context->'trace'->>'traceId' = ?)",
          values: [ trace, trace, trace ]
        }
      end

      if request.present?
        conditions << {
          sql: "(context->>'request_id' = ? OR context->>'requestId' = ? OR context->'trace'->>'requestId' = ?)",
          values: [ request, request, request ]
        }
      end

      if session.present?
        conditions << {
          sql: "(context->>'session_id' = ? OR context->>'sessionId' = ?)",
          values: [ session, session ]
        }
      end

      if user.present?
        conditions << {
          sql: "(context->>'user_id' = ? OR context->>'userId' = ? OR context->'user'->>'id' = ?)",
          values: [ user, user, user ]
        }
      end

      conditions
    end
  end
end
