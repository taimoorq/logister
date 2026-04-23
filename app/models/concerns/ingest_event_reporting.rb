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

    private

    def grouped_count(relation, field)
      relation.group(field).count(:all)
    end
  end
end
