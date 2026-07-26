# frozen_string_literal: true

class ErrorGroupImpactSummary
  Metric = Data.define(:value, :state, :sampled_events, :total_events) do
    def available?
      state == :available
    end
  end

  Summary = Data.define(
    :error_group_id,
    :events,
    :installations,
    :sessions,
    :users,
    :first_release,
    :last_release,
    :top_device,
    :top_os,
    :series
  )

  COHORT_DIMENSIONS = {
    top_device: "device_model",
    top_os: "os_version"
  }.freeze

  class << self
    def for_group(group, since: 30.days.ago)
      for_groups([ group ], since: since).fetch(group.id)
    end

    def for_groups(groups, since: 30.days.ago)
      group_ids = Array(groups).map(&:id).compact
      return {} if group_ids.empty?

      new(group_ids: group_ids, since: since).call
    end
  end

  attr_reader :group_ids, :since

  def initialize(group_ids:, since:)
    @group_ids = group_ids
    @since = since
  end

  def call
    aggregates = aggregate_rows
    releases = release_rows
    cohorts = cohort_rows
    trends = trend_rows

    group_ids.index_with do |group_id|
      aggregate = aggregates.fetch(group_id, default_aggregate)
      total = aggregate.fetch(:events)
      release_values = releases.fetch(group_id, [])

      Summary.new(
        error_group_id: group_id,
        events: total,
        installations: metric(aggregate.fetch(:installations), aggregate.fetch(:installation_samples), total),
        sessions: metric(aggregate.fetch(:sessions), aggregate.fetch(:session_samples), total),
        users: metric(aggregate.fetch(:users), aggregate.fetch(:user_samples), total),
        first_release: release_values.first,
        last_release: release_values.last,
        top_device: cohorts.dig(group_id, :top_device),
        top_os: cohorts.dig(group_id, :top_os),
        series: trends.fetch(group_id, [])
      )
    end
  end

  private

  def scope
    ErrorOccurrence.where(error_group_id: group_ids).where("occurred_at >= ?", since)
  end

  def aggregate_rows
    scope.group(:error_group_id).pluck(
      :error_group_id,
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(DISTINCT installation_hash) FILTER (WHERE installation_hash IS NOT NULL)"),
      Arel.sql("COUNT(installation_hash)"),
      Arel.sql("COUNT(DISTINCT session_hash) FILTER (WHERE session_hash IS NOT NULL)"),
      Arel.sql("COUNT(session_hash)"),
      Arel.sql("COUNT(DISTINCT user_hash) FILTER (WHERE user_hash IS NOT NULL)"),
      Arel.sql("COUNT(user_hash)")
    ).to_h do |row|
      group_id, events, installations, installation_samples, sessions, session_samples, users, user_samples = row
      [ group_id, {
        events: events.to_i,
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
    COHORT_DIMENSIONS.each do |name, dimension|
      rows = scope.where("COALESCE(dimensions ->> ?, '') <> ''", dimension)
                  .group(:error_group_id, Arel.sql("dimensions ->> #{ActiveRecord::Base.connection.quote(dimension)}"))
                  .order(Arel.sql("COUNT(*) DESC"))
                  .count
      rows.each do |(group_id, value), count|
        result[group_id][name] ||= { value: value, events: count }
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
    if sample_count.positive?
      Metric.new(value: distinct_count, state: :available, sampled_events: sample_count, total_events: total)
    else
      Metric.new(value: nil, state: :not_collected, sampled_events: 0, total_events: total)
    end
  end

  def default_aggregate
    {
      events: 0,
      installations: 0,
      installation_samples: 0,
      sessions: 0,
      session_samples: 0,
      users: 0,
      user_samples: 0
    }
  end
end
