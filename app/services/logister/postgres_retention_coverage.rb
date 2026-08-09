# frozen_string_literal: true

module Logister
  class PostgresRetentionCoverage
    EVENT_SIGNALS = %w[error metric transaction log check_in].freeze
    SUPPORTED_SIGNALS = (EVENT_SIGNALS + [ "span" ]).freeze

    Policy = Data.define(:project_id, :hot_retention_days, :trace_retention_days, :error_retention_days)

    Result = Data.define(:complete, :reason, :requested_from, :requested_to, :retained_from) do
      def complete?
        complete
      end

      def to_h
        {
          complete: complete?,
          reason: reason,
          requested_from: requested_from&.utc&.iso8601,
          requested_to: requested_to&.utc&.iso8601,
          retained_from: retained_from&.utc&.iso8601
        }
      end
    end

    class Repository
      def policies_for(project_ids:)
        Project.left_outer_joins(:retention_policy)
               .where(id: project_ids)
               .pluck(
                 "projects.id",
                 "project_retention_policies.hot_retention_days",
                 "project_retention_policies.trace_retention_days",
                 "project_retention_policies.error_retention_days"
               )
               .map do |project_id, hot_days, trace_days, error_days|
          Policy.new(
            project_id,
            hot_days || ProjectRetentionPolicy::DEFAULT_HOT_RETENTION_DAYS,
            trace_days || ProjectRetentionPolicy::DEFAULT_TRACE_RETENTION_DAYS,
            error_days
          )
        end
      end
    end

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(project_ids:, signals:, from:, to:, repository: Repository.new, now: Time.current)
      @project_ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq.sort
      @signals = Array(signals).map(&:to_s).uniq.sort
      @requested_from = from.to_time.utc
      @requested_to = to.to_time.utc
      @repository = repository
      @now = now.to_time.utc
    end

    def call
      return result(complete: false, reason: "invalid_range") if @requested_to <= @requested_from
      return result(complete: false, reason: "invalid_scope") if @project_ids.empty? || @signals.empty?
      return result(complete: false, reason: "unsupported_signals") if (@signals - SUPPORTED_SIGNALS).any?

      policies = @repository.policies_for(project_ids: @project_ids)
      return result(complete: false, reason: "missing_projects") if policies.map(&:project_id).sort != @project_ids

      retained_from = policies.flat_map { |policy| @signals.filter_map { |signal| cutoff_for(policy, signal) } }.max
      complete = retained_from.nil? || @requested_from >= retained_from

      result(
        complete: complete,
        reason: complete ? "within_postgres_retention" : "postgres_retention_window",
        retained_from:
      )
    end

    private

    def cutoff_for(policy, signal)
      days = case signal
      when "span"
        policy.trace_retention_days
      when "error"
        policy.error_retention_days
      else
        policy.hot_retention_days
      end

      @now - days.days if days.present?
    end

    def result(complete:, reason:, retained_from: nil)
      Result.new(complete, reason, @requested_from, @requested_to, retained_from)
    end
  end
end
