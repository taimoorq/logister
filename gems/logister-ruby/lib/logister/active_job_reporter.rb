require_relative "context_helpers"
require_relative "context_store"

module Logister
  module ActiveJobReporter
    def self.install!
      return unless defined?(ActiveJob::Base)
      return if ActiveJob::Base < Logister::ActiveJobReporter::Instrumentation

      ActiveJob::Base.include(Logister::ActiveJobReporter::Instrumentation)
    end

    module Instrumentation
      extend ActiveSupport::Concern

      included do
        around_perform do |job, block|
          Logister::ContextStore.reset_request_scope!
          Logister.add_breadcrumb(
            category: "job",
            message: "Starting #{job.class.name}",
            data: { queue: job.queue_name, jobId: job.job_id }
          )
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            block.call
          rescue StandardError => error
            Logister.report_error(
              error,
              context: Logister::ActiveJobReporter.build_job_error_context(job, started_at: started_at)
            )
            raise
          ensure
            Logister::ContextStore.reset_request_scope!
          end
        end
      end
    end

    module_function

    def build_job_error_context(job, started_at:)
      Logister::ContextHelpers.compact_deep(
        {
          job: {
            jobClass: job.class.name.to_s,
            jobId: job.job_id.to_s.presence,
            providerJobId: job.provider_job_id.to_s.presence,
            queue: job.queue_name.to_s.presence,
            priority: job.priority,
            executions: job.executions,
            exceptionExecutions: serialize_exception_executions(job),
            locale: job.locale.to_s.presence,
            timezone: (job.respond_to?(:timezone) ? job.timezone.to_s.presence : nil),
            enqueuedAt: (job.respond_to?(:enqueued_at) ? time_to_iso8601(job.enqueued_at) : nil),
            scheduledAt: time_to_iso8601(job.scheduled_at),
            arguments: Logister::ContextHelpers.filtered_job_arguments(job)
          }.compact,
          breadcrumbs: Logister::ContextStore.breadcrumbs.presence,
          dependencyCalls: Logister::ContextStore.dependencies.presence,
          runtime: Logister::ContextHelpers.runtime_context[:runtime],
          deployment: Logister::ContextHelpers.deployment_context[:deployment]
        }
      )
    end

    def serialize_exception_executions(job)
      raw = job.respond_to?(:exception_executions) ? job.exception_executions : nil
      return nil if raw.nil?

      raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : raw
    end

    def time_to_iso8601(value)
      return nil unless value.respond_to?(:iso8601)

      value.iso8601
    rescue StandardError
      nil
    end
  end
end
