# frozen_string_literal: true

module ProjectInbox
  class EvidenceSignalQuery
    CURRENT_WINDOW = 24.hours
    REPETITIVE_WINDOW = 7.days
    MIN_CURRENT_EVENTS = 10
    MIN_PREVIOUS_EVENTS = 5
    MIN_SPIKE_DELTA = 5
    MIN_SPIKE_RATIO = 2.0
    MIN_IDENTITY_COVERAGE = 0.8
    MIN_EVENTS_PER_IDENTITY = 4.0
    EARLY_SESSION_THRESHOLD_MS = 5_000
    MIN_TIMED_SESSION_EVENTS = 5
    MIN_SESSION_TIMING_COVERAGE = 0.8
    MIN_EARLY_SESSION_SHARE = 0.6
    MIN_DIAGNOSTIC_COST_EVENTS = 5
    MIN_DIAGNOSTIC_COST_RATIO = 2.0
    DIAGNOSTIC_COST_LABELS = {
      "hang_duration" => "hang time",
      "total_cpu_time" => "CPU time",
      "total_bytes_written" => "disk writes",
      "launch_duration" => "launch time"
    }.freeze

    Signal = Data.define(:key, :label, :concise_label, :title, :evidence)

    def self.call(...)
      new(...).call
    end

    attr_reader :occurrence_scope, :group_ids, :now

    def initialize(occurrence_scope:, group_ids:, now: Time.current)
      @occurrence_scope = occurrence_scope
      @group_ids = Array(group_ids).map(&:to_i).uniq
      @now = now
    end

    def call
      return {} if group_ids.empty?

      cost_signals = diagnostic_cost_signals
      evidence_rows.to_h do |row|
        group_id, current, previous, total, installation_identified, installations,
          session_identified, sessions, session_timed, early_session = row.map(&:to_i)
        signal = spike_signal(current:, previous:) || cost_signals[group_id] || repetitive_signal(
          total:,
          installation_identified:,
          installations:,
          session_identified:,
          sessions:
        ) || early_session_signal(total:, session_timed:, early_session:)
        [ group_id, signal ]
      end.compact.merge(cost_signals) { |_group_id, standard, _cost| standard }
    end

    private

    def evidence_rows
      current_start = now - CURRENT_WINDOW
      previous_start = current_start - CURRENT_WINDOW
      repetitive_start = now - REPETITIVE_WINDOW
      earliest = [ previous_start, repetitive_start ].min

      occurrence_scope
        .where(error_group_id: group_ids)
        .where("error_occurrences.occurred_at >= ? AND error_occurrences.occurred_at < ?", earliest, now)
        .where("error_occurrences.dimensions ->> 'time_precision' = 'exact'")
        .group(:error_group_id)
        .pluck(
          :error_group_id,
          Arel.sql(count_between_sql(current_start, now)),
          Arel.sql(count_between_sql(previous_start, current_start)),
          Arel.sql(count_between_sql(repetitive_start, now)),
          Arel.sql(count_identity_sql("installation_hash", repetitive_start)),
          Arel.sql(count_distinct_identity_sql("installation_hash", repetitive_start)),
          Arel.sql(count_identity_sql("session_hash", repetitive_start)),
          Arel.sql(count_distinct_identity_sql("session_hash", repetitive_start)),
          Arel.sql(count_session_timing_sql(repetitive_start)),
          Arel.sql(count_early_session_sql(repetitive_start))
        )
    end

    def diagnostic_cost_signals
      diagnostic_cost_rows
        .group_by(&:first)
        .transform_values { |rows| diagnostic_cost_signal(rows) }
        .compact
    end

    def diagnostic_cost_rows
      dimensions = "error_occurrences.dimensions"
      occurrence_scope
        .where(error_group_id: group_ids)
        .where("#{dimensions} ->> 'time_precision' = 'reporting_interval'")
        .where("#{dimensions} ->> 'diagnostic_measurement' IN (?)", DIAGNOSTIC_COST_LABELS.keys)
        .where("#{dimensions} ->> 'diagnostic_measurement_value' ~ ?", "^[0-9]+(?:\\.[0-9]+)?$")
        .where("#{dimensions} ->> 'reporting_start_at' ~ ?", "^\\d{4}-\\d{2}-\\d{2}T")
        .where("#{dimensions} ->> 'reporting_end_at' ~ ?", "^\\d{4}-\\d{2}-\\d{2}T")
        .group(
          :error_group_id,
          Arel.sql("#{dimensions} ->> 'diagnostic_measurement'"),
          Arel.sql("#{dimensions} ->> 'diagnostic_measurement_unit'"),
          Arel.sql("#{dimensions} ->> 'reporting_start_at'"),
          Arel.sql("#{dimensions} ->> 'reporting_end_at'")
        )
        .pluck(
          :error_group_id,
          Arel.sql("#{dimensions} ->> 'diagnostic_measurement'"),
          Arel.sql("#{dimensions} ->> 'diagnostic_measurement_unit'"),
          Arel.sql("#{dimensions} ->> 'reporting_start_at'"),
          Arel.sql("#{dimensions} ->> 'reporting_end_at'"),
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM((#{dimensions} ->> 'diagnostic_measurement_value')::numeric)")
        )
    end

    def diagnostic_cost_signal(rows)
      intervals = rows.filter_map do |group_id, measurement, unit, start_value, end_value, count, total|
        start_at = parse_time(start_value)
        end_at = parse_time(end_value)
        next unless start_at && end_at && end_at > start_at && end_at <= now

        {
          group_id:,
          measurement:,
          unit: unit.to_s,
          start_at:,
          end_at:,
          count: count.to_i,
          total: total.to_f
        }
      end
      signals = intervals.group_by { |row| [ row[:measurement], row[:unit] ] }.filter_map do |_key, series|
        current = series.max_by { |row| row[:end_at] }
        prior = series
          .select { |row| comparable_intervals?(prior: row, current:) }
          .max_by { |row| row[:end_at] }
        build_diagnostic_cost_signal(current:, prior:)
      end
      signals.max_by { |signal| signal.evidence.fetch("ratio") }
    end

    def comparable_intervals?(prior:, current:)
      return false unless prior[:end_at] <= current[:start_at]

      current_duration = current[:end_at] - current[:start_at]
      prior_duration = prior[:end_at] - prior[:start_at]
      duration_tolerance = [ current_duration * 0.05, 60 ].max
      gap_tolerance = [ current_duration * 0.1, 60 ].max
      (current_duration - prior_duration).abs <= duration_tolerance &&
        current[:start_at] - prior[:end_at] <= gap_tolerance
    end

    def build_diagnostic_cost_signal(current:, prior:)
      return unless current && prior
      return if current[:count] < MIN_DIAGNOSTIC_COST_EVENTS || prior[:count] < MIN_DIAGNOSTIC_COST_EVENTS
      return unless prior[:total].positive?

      ratio = current[:total].fdiv(prior[:total])
      return if ratio < MIN_DIAGNOSTIC_COST_RATIO

      label = DIAGNOSTIC_COST_LABELS.fetch(current[:measurement])
      Signal.new(
        key: :diagnostic_cost,
        label: "Cost increased",
        concise_label: format("%.1f× %s", ratio, label),
        title: "Comparable #{label} increased from #{format_cost(prior[:total], current[:unit])} to #{format_cost(current[:total], current[:unit])} across adjacent reporting intervals with #{prior[:count]} and #{current[:count]} diagnostics.",
        evidence: {
          "time_precision" => "reporting_interval",
          "measurement" => current[:measurement],
          "unit" => current[:unit],
          "current_reporting_start" => current[:start_at].utc.iso8601,
          "current_reporting_end" => current[:end_at].utc.iso8601,
          "previous_reporting_start" => prior[:start_at].utc.iso8601,
          "previous_reporting_end" => prior[:end_at].utc.iso8601,
          "current_events" => current[:count],
          "previous_events" => prior[:count],
          "current_total" => current[:total],
          "previous_total" => prior[:total],
          "ratio" => ratio.round(3),
          "minimum_events_per_interval" => MIN_DIAGNOSTIC_COST_EVENTS
        }
      ).freeze
    end

    def format_cost(value, unit)
      number = value.to_i == value ? value.to_i : value.round(2)
      "#{number} #{unit}"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def count_between_sql(start_at, end_at)
      sanitize_sql_array([
        "COUNT(*) FILTER (WHERE error_occurrences.occurred_at >= ? AND error_occurrences.occurred_at < ?)",
        start_at,
        end_at
      ])
    end

    def count_identity_sql(column, start_at)
      sanitize_sql_array([
        "COUNT(error_occurrences.#{column}) FILTER (WHERE error_occurrences.occurred_at >= ? AND error_occurrences.occurred_at < ?)",
        start_at,
        now
      ])
    end

    def count_distinct_identity_sql(column, start_at)
      sanitize_sql_array([
        "COUNT(DISTINCT error_occurrences.#{column}) FILTER (WHERE error_occurrences.occurred_at >= ? AND error_occurrences.occurred_at < ?)",
        start_at,
        now
      ])
    end

    def count_session_timing_sql(start_at)
      sanitize_sql_array([
        <<~SQL.squish,
          COUNT(*) FILTER (
            WHERE error_occurrences.occurred_at >= ?
              AND error_occurrences.occurred_at < ?
              AND error_occurrences.dimensions ->> 'session_age_ms' ~ '^[0-9]+$'
          )
        SQL
        start_at,
        now
      ])
    end

    def count_early_session_sql(start_at)
      sanitize_sql_array([
        <<~SQL.squish,
          COUNT(*) FILTER (
            WHERE error_occurrences.occurred_at >= ?
              AND error_occurrences.occurred_at < ?
              AND error_occurrences.dimensions ->> 'session_age_ms' ~ '^[0-9]+$'
              AND (error_occurrences.dimensions ->> 'session_age_ms')::bigint <= ?
          )
        SQL
        start_at,
        now,
        EARLY_SESSION_THRESHOLD_MS
      ])
    end

    def sanitize_sql_array(value)
      ActiveRecord::Base.sanitize_sql_array(value)
    end

    def spike_signal(current:, previous:)
      return if current < MIN_CURRENT_EVENTS || previous < MIN_PREVIOUS_EVENTS
      return if current - previous < MIN_SPIKE_DELTA

      ratio = current.fdiv(previous)
      return if ratio < MIN_SPIKE_RATIO

      increase = ((ratio - 1) * 100).round
      Signal.new(
        key: :spiking,
        label: "Spiking",
        concise_label: "+#{increase}% in 24h",
        title: "#{current} exact-time events in the latest 24 hours versus #{previous} in the prior 24 hours.",
        evidence: {
          "time_precision" => "exact",
          "current_window_hours" => 24,
          "current_events" => current,
          "previous_events" => previous,
          "increase_percent" => increase,
          "minimum_current_events" => MIN_CURRENT_EVENTS,
          "minimum_previous_events" => MIN_PREVIOUS_EVENTS
        }
      ).freeze
    end

    def repetitive_signal(total:, installation_identified:, installations:, session_identified:, sessions:)
      return if total < MIN_CURRENT_EVENTS

      identity = repetitive_identity(
        total:,
        installation_identified:,
        installations:,
        session_identified:,
        sessions:
      )
      return unless identity

      kind, identified, distinct = identity
      average = identified.fdiv(distinct)
      return if average < MIN_EVENTS_PER_IDENTITY

      coverage = identified.fdiv(total)
      plural = kind == :installation ? "installations" : "sessions"
      Signal.new(
        key: :repetitive,
        label: "Repetitive",
        concise_label: format("%.1f events/%s", average, kind),
        title: "#{identified} of #{total} exact-time events came from #{distinct} identified #{plural} in 7 days (#{(coverage * 100).round}% identity coverage).",
        evidence: {
          "time_precision" => "exact",
          "window_days" => 7,
          "identity_kind" => kind.to_s,
          "identified_events" => identified,
          "total_events" => total,
          "distinct_identities" => distinct,
          "identity_coverage" => coverage.round(4),
          "events_per_identity" => average.round(2)
        }
      ).freeze
    end

    def repetitive_identity(total:, installation_identified:, installations:, session_identified:, sessions:)
      if installations.positive? && installation_identified.fdiv(total) >= MIN_IDENTITY_COVERAGE
        [ :installation, installation_identified, installations ]
      elsif sessions.positive? && session_identified.fdiv(total) >= MIN_IDENTITY_COVERAGE
        [ :session, session_identified, sessions ]
      end
    end

    def early_session_signal(total:, session_timed:, early_session:)
      return if session_timed < MIN_TIMED_SESSION_EVENTS || total.zero?

      coverage = session_timed.fdiv(total)
      share = early_session.fdiv(session_timed)
      return if coverage < MIN_SESSION_TIMING_COVERAGE || share < MIN_EARLY_SESSION_SHARE

      percent = (share * 100).round
      Signal.new(
        key: :early_session,
        label: "Early session",
        concise_label: "#{percent}% in first 5s",
        title: "#{early_session} of #{session_timed} exact-time events with valid session timing occurred in the first 5 seconds (#{(coverage * 100).round}% timing coverage across #{total} events).",
        evidence: {
          "time_precision" => "exact",
          "window_days" => 7,
          "threshold_ms" => EARLY_SESSION_THRESHOLD_MS,
          "timed_events" => session_timed,
          "early_events" => early_session,
          "total_events" => total,
          "timing_coverage" => coverage.round(4),
          "early_share" => share.round(4)
        }
      ).freeze
    end
  end
end
