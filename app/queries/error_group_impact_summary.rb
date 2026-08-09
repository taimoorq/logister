# frozen_string_literal: true

class ErrorGroupImpactSummary
  Metric = Data.define(:value, :state, :sampled_events, :total_events) do
    def available?
      %i[complete partial sampled].include?(state)
    end

    def complete?
      state == :complete
    end
  end

  Summary = Data.define(
    :error_group_id,
    :events,
    :first_seen_at,
    :last_seen_at,
    :installations,
    :sessions,
    :users,
    :first_release,
    :last_release,
    :top_device,
    :top_os,
    :device_over_index,
    :os_over_index,
    :series
  )

  CohortIndex = Data.define(
    :value,
    :issue_events,
    :issue_observed_events,
    :baseline_events,
    :baseline_observed_events,
    :issue_share,
    :baseline_share,
    :lift,
    :state
  ) do
    def over_indexed?
      state == :over_indexed
    end
  end

  COHORT_DIMENSIONS = {
    top_device: "device_model",
    top_os: "os_version"
  }.freeze

  class << self
    def for_group(group, since: 30.days.ago, occurrence_scope: nil, baseline_scope: nil)
      for_groups([ group ], since: since, occurrence_scope: occurrence_scope, baseline_scope: baseline_scope).fetch(group.id)
    end

    def for_groups(groups, since: 30.days.ago, occurrence_scope: nil, baseline_scope: nil)
      group_ids = Array(groups).map(&:id).compact
      return {} if group_ids.empty?

      new(group_ids: group_ids, since: since, occurrence_scope: occurrence_scope, baseline_scope: baseline_scope).call
    end
  end

  attr_reader :group_ids, :since, :occurrence_scope, :baseline_scope

  def initialize(group_ids:, since:, occurrence_scope: nil, baseline_scope: nil)
    @group_ids = group_ids
    @since = since
    @occurrence_scope = occurrence_scope
    @baseline_scope = baseline_scope
  end

  def call
    aggregates = aggregate_rows
    releases = release_rows
    cohorts = cohort_rows
    cohort_indexes = cohort_index_rows
    trends = trend_rows

    group_ids.index_with do |group_id|
      aggregate = aggregates.fetch(group_id, default_aggregate)
      total = aggregate.fetch(:events)
      release_values = releases.fetch(group_id, [])

      Summary.new(
        error_group_id: group_id,
        events: total,
        first_seen_at: aggregate.fetch(:first_seen_at),
        last_seen_at: aggregate.fetch(:last_seen_at),
        installations: metric(aggregate.fetch(:installations), aggregate.fetch(:installation_samples), total),
        sessions: metric(aggregate.fetch(:sessions), aggregate.fetch(:session_samples), total),
        users: metric(aggregate.fetch(:users), aggregate.fetch(:user_samples), total),
        first_release: release_values.first,
        last_release: release_values.last,
        top_device: cohorts.dig(group_id, :top_device),
        top_os: cohorts.dig(group_id, :top_os),
        device_over_index: cohort_indexes.dig(group_id, :top_device),
        os_over_index: cohort_indexes.dig(group_id, :top_os),
        series: trends.fetch(group_id, [])
      )
    end
  end

  private

  def scope
    value = occurrence_scope || ErrorOccurrence.all
    value = value.where(error_group_id: group_ids)
    since ? value.where("occurred_at >= ?", since) : value
  end

  def aggregate_rows
    scope.group(:error_group_id).pluck(
      :error_group_id,
      Arel.sql("COUNT(*)"),
      Arel.sql("MIN(occurred_at)"),
      Arel.sql("MAX(occurred_at)"),
      Arel.sql("COUNT(DISTINCT installation_hash) FILTER (WHERE installation_hash IS NOT NULL)"),
      Arel.sql("COUNT(installation_hash)"),
      Arel.sql("COUNT(DISTINCT session_hash) FILTER (WHERE session_hash IS NOT NULL)"),
      Arel.sql("COUNT(session_hash)"),
      Arel.sql("COUNT(DISTINCT user_hash) FILTER (WHERE user_hash IS NOT NULL)"),
      Arel.sql("COUNT(user_hash)")
    ).to_h do |row|
      group_id, events, first_seen_at, last_seen_at, installations, installation_samples, sessions, session_samples, users, user_samples = row
      [ group_id, {
        events: events.to_i,
        first_seen_at: first_seen_at,
        last_seen_at: last_seen_at,
        installations: installations.to_i,
        installation_samples: installation_samples.to_i,
        sessions: sessions.to_i,
        session_samples: session_samples.to_i,
        users: users.to_i,
        user_samples: user_samples.to_i
      } ]
    end
  end

  def release_rows
    scope.where.not(release: [ nil, "" ])
         .order(:error_group_id, :occurred_at, :id)
         .pluck(:error_group_id, :release)
         .each_with_object({}) do |(group_id, release), values|
      (values[group_id] ||= []) << release unless values.fetch(group_id, []).last == release
    end
  end

  def cohort_rows
    result = Hash.new { |hash, key| hash[key] = {} }
    @cohort_counts = Hash.new { |hash, name| hash[name] = Hash.new { |groups, group_id| groups[group_id] = {} } }
    COHORT_DIMENSIONS.each do |name, dimension|
      rows = scope.where("COALESCE(dimensions ->> ?, '') <> ''", dimension)
                  .group(:error_group_id, Arel.sql("dimensions ->> #{ActiveRecord::Base.connection.quote(dimension)}"))
                  .order(Arel.sql("COUNT(*) DESC"))
                  .count
      rows.each do |(group_id, value), count|
        @cohort_counts[name][group_id][value] = count.to_i
        result[group_id][name] ||= { value: value, events: count }
      end
    end
    result
  end

  def cohort_index_rows
    return {} unless baseline_scope

    result = Hash.new { |hash, group_id| hash[group_id] = {} }
    COHORT_DIMENSIONS.each do |name, dimension|
      baseline_counts = baseline_scope
        .where("COALESCE(dimensions ->> ?, '') <> ''", dimension)
        .group(Arel.sql("dimensions ->> #{ActiveRecord::Base.connection.quote(dimension)}"))
        .count
        .transform_values(&:to_i)
      baseline_total = baseline_counts.values.sum
      next if baseline_total.zero?

      group_ids.each do |group_id|
        issue_counts = @cohort_counts.fetch(name, {}).fetch(group_id, {})
        issue_total = issue_counts.values.sum
        value, issue_events = issue_counts.max_by { |cohort_value, count| [ count, cohort_value.to_s ] }
        next unless value && issue_total.positive?

        baseline_events = baseline_counts.fetch(value, 0)
        issue_share = issue_events.fdiv(issue_total)
        baseline_share = baseline_events.fdiv(baseline_total)
        lift = baseline_share.positive? ? issue_share.fdiv(baseline_share) : nil
        state = if issue_total >= 10 && baseline_total >= 100 && issue_share >= 0.5 &&
            baseline_share.positive? && lift >= 2.0 && issue_share - baseline_share >= 0.2
          :over_indexed
        else
          :top_only
        end
        result[group_id][name] = CohortIndex.new(
          value:,
          issue_events:,
          issue_observed_events: issue_total,
          baseline_events:,
          baseline_observed_events: baseline_total,
          issue_share: issue_share.round(4),
          baseline_share: baseline_share.round(4),
          lift: lift&.round(2),
          state:
        )
      end
    end
    result
  end

  def trend_rows
    scope.group(:error_group_id, Arel.sql("DATE(occurred_at)"))
         .order(Arel.sql("DATE(occurred_at) ASC"))
         .count
         .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((group_id, date), count), values|
      values[group_id] << { date: date.to_date, events: count }
    end
  end

  def metric(distinct_count, sample_count, total)
    return Metric.new(value: nil, state: :not_applicable, sampled_events: 0, total_events: 0) if total.zero?
    return Metric.new(value: nil, state: :not_collected, sampled_events: 0, total_events: total) if sample_count.zero?

    state = sample_count == total ? :complete : :partial
    Metric.new(value: distinct_count, state: state, sampled_events: sample_count, total_events: total)
  end

  def default_aggregate
    {
      events: 0,
      first_seen_at: nil,
      last_seen_at: nil,
      installations: 0,
      installation_samples: 0,
      sessions: 0,
      session_samples: 0,
      users: 0,
      user_samples: 0
    }
  end
end
