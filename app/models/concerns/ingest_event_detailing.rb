module IngestEventDetailing
  extend ActiveSupport::Concern

  class_methods do
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
