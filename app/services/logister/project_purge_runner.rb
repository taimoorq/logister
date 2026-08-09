# frozen_string_literal: true

module Logister
  class ProjectPurgeRunner
    ADAPTERS = {
      "archives" => "Logister::ProjectPurgeAdapters::Archives",
      "redis" => "Logister::ProjectPurgeAdapters::RedisDerived",
      "postgresql" => "Logister::ProjectPurgeAdapters::Postgresql",
      "clickhouse" => "Logister::ProjectPurgeAdapters::Clickhouse"
    }.freeze

    def initialize(project_purge:, adapters: {}, run_lock: nil)
      @project_purge = project_purge
      @adapters = adapters.stringify_keys
      @run_lock = run_lock || ProjectPurgeLock.new(project_purge_id: project_purge.id)
    end

    def call
      return concurrent_result unless @run_lock.acquire

      call_as_owner
    ensure
      @run_lock.release
    end

    private

    def call_as_owner
      @project_purge.reload
      return terminal_result if @project_purge.completed?

      start_run!
      @project_purge.steps.reload.each do |step|
        next if step.terminal?

        outcome = run_step!(step)
        return awaiting_external_result(step, outcome) if outcome.fetch(:status).to_s == "awaiting_external"
      end

      verify_and_complete!
      terminal_result
    rescue StandardError => error
      fail_run!(error)
      raise
    end

    def start_run!
      now = Time.current
      @project_purge.update!(
        status: "running",
        started_at: @project_purge.started_at || now,
        attempts: @project_purge.attempts.to_i + 1,
        failed_at: nil,
        last_error_class: nil,
        last_error_message: nil,
        last_error_at: nil
      )
      @project_purge.append_audit!("run_started", { "attempt" => @project_purge.attempts }, at: now)
    end

    def run_step!(step)
      now = Time.current
      step.update!(
        status: "running",
        started_at: step.started_at || now,
        attempts: step.attempts.to_i + 1,
        failed_at: nil,
        last_error_class: nil,
        last_error_message: nil,
        last_error_at: nil
      )
      @project_purge.update!(current_step: step.store_name)
      @project_purge.append_audit!(
        "step_started",
        { "store" => step.store_name, "attempt" => step.attempts },
        at: now
      )

      outcome = adapter_for(step.store_name).call.symbolize_keys
      status = outcome.fetch(:status).to_s
      unless status.in?(%w[completed skipped awaiting_external])
        raise ArgumentError, "Purge adapter returned unsupported status #{status.inspect}"
      end

      step.update!(
        status: status,
        result: outcome.except(:status).as_json,
        completed_at: (Time.current if status.in?(%w[completed skipped]))
      )
      @project_purge.append_audit!(
        "step_#{status}",
        { "store" => step.store_name, "result" => step.result },
        at: Time.current
      )
      outcome
    rescue StandardError => error
      step.update_columns(
        status: "failed",
        failed_at: Time.current,
        last_error_at: Time.current,
        last_error_class: error.class.name,
        last_error_message: error.message,
        updated_at: Time.current
      )
      raise
    end

    def adapter_for(store_name)
      @adapters.fetch(store_name) do
        ADAPTERS.fetch(store_name).constantize.new(project_purge: @project_purge)
      end
    end

    def awaiting_external_result(step, outcome)
      @project_purge.update!(status: "awaiting_external", current_step: step.store_name)
      schedule_automatic_retry(outcome[:retry_at])
      {
        project_purge_id: @project_purge.id,
        status: "awaiting_external",
        current_step: step.store_name,
        result: outcome.except(:status)
      }
    end

    def schedule_automatic_retry(retry_at)
      return if retry_at.blank?

      parsed = Time.zone.parse(retry_at.to_s)
      return unless parsed

      ProjectPurgeJob.set(wait_until: parsed).perform_later(@project_purge.id)
    end

    def verify_and_complete!
      @project_purge.update!(status: "verifying", current_step: nil)
      incomplete = @project_purge.steps.reload.reject(&:terminal?)
      if incomplete.any?
        raise "Project purge has incomplete steps: #{incomplete.map { |step| "#{step.store_name}=#{step.status}" }.join(', ')}"
      end
      if Project.exists?(id: @project_purge.source_project_id)
        raise "Project still exists after PostgreSQL purge verification"
      end

      now = Time.current
      @project_purge.update!(status: "completed", completed_at: now, current_step: nil)
      @project_purge.append_audit!(
        "completed",
        { "stores" => @project_purge.steps.pluck(:store_name, :status).to_h },
        at: now
      )
    end

    def fail_run!(error)
      return unless @project_purge&.persisted?

      @project_purge.reload
      return if @project_purge.completed?

      now = Time.current
      @project_purge.update_columns(
        status: "failed",
        failed_at: now,
        last_error_at: now,
        last_error_class: error.class.name,
        last_error_message: error.message,
        updated_at: now
      )
      @project_purge.append_audit!(
        "failed",
        { "class" => error.class.name, "message" => error.message, "step" => @project_purge.current_step },
        at: now
      )
    rescue StandardError => audit_error
      Rails.logger.error(
        "project_purge.audit_failed purge_id=#{@project_purge.id} " \
        "error=#{audit_error.class}: #{audit_error.message}"
      )
    end

    def concurrent_result
      @project_purge.reload
      {
        project_purge_id: @project_purge.id,
        project_uuid: @project_purge.project_uuid,
        status: @project_purge.status,
        current_step: @project_purge.current_step,
        already_running: true
      }
    end

    def terminal_result
      {
        project_purge_id: @project_purge.id,
        project_uuid: @project_purge.project_uuid,
        status: @project_purge.status,
        completed_at: @project_purge.completed_at&.utc&.iso8601,
        steps: @project_purge.steps.order(:position).map do |step|
          { store: step.store_name, status: step.status, result: step.result }
        end
      }
    end
  end
end
