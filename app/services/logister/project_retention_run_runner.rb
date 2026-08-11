# frozen_string_literal: true

require "securerandom"

module Logister
  class ProjectRetentionRunRunner
    class LeaseLost < StandardError; end

    DEFAULT_OBJECTS_PER_ATTEMPT = 25
    DEFAULT_MAX_FAILURES = 10
    CONTINUATION_DELAY = 1.second

    Attempt = Data.define(:token, :fence_version)

    def initialize(run:, storage_service: nil, now: nil, clock: nil)
      @run = run
      @storage_service = storage_service
      @clock = clock || (now ? -> { now } : -> { Time.current })
      @now = now || current_time
      @lock = nil
      @attempt = nil
    end

    def call
      @attempt = claim!
      unless @attempt
        telemetry("delivery_noop", action: "noop")
        return { action: :noop, status: @run.reload.status }
      end
      telemetry("attempt_claimed")

      @lock = ProjectRetentionLock.new(project_id: @run.project_id, dry_run: @run.dry_run?)
      unless @lock.acquire
        release_for_continuation!(reason: "project_lock_unavailable")
        return { action: :continue, wait: CONTINUATION_DELAY, status: "queued" }
      end

      assert_current_attempt!
      result = ProjectRetentionRunner.new(
        project: @run.project,
        dry_run: @run.dry_run?,
        now: @run.scheduled_for,
        run: @run,
        archive_object_limit: objects_per_attempt,
        cleanup_object_limit: objects_per_attempt,
        write_fence: method(:assert_current_attempt!),
        storage_service: @storage_service,
        cutoff_snapshot: @run.cutoff_snapshot,
        clock: @clock
      ).call

      if result.fetch(:continuation_required, false)
        checkpoint_continuation!(result)
        { action: :continue, wait: CONTINUATION_DELAY, status: "queued", result: result }
      else
        complete!(result)
        { action: :complete, status: "completed", result: result }
      end
    rescue LeaseLost
      telemetry("attempt_fenced", action: "fenced")
      { action: :fenced, status: @run.reload.status }
    rescue StandardError => error
      failure_result(error)
    ensure
      @lock&.release
    end

    def assert_current_attempt!
      ProjectRetentionRun.transaction(requires_new: true) do
        current = ProjectRetentionRun.lock.find(@run.id)
        unless current.status == "running" &&
            current.attempt_token == @attempt&.token &&
            current.fence_version == @attempt&.fence_version
          raise LeaseLost, "Retention attempt #{@attempt&.token} lost fence #{@attempt&.fence_version}"
        end

        heartbeat_at = current_time
        current.update_columns(heartbeat_at: heartbeat_at, updated_at: heartbeat_at)
      end
      true
    end

    private

    def claim!
      @run.with_lock do
        @run.reload
        return if @run.terminal?
        return if @run.status == "running" && !@run.stale?(before: @now - stale_after)
        return if @run.available_at.present? && @run.available_at > @now

        token = SecureRandom.uuid
        fence = @run.fence_version.to_i + 1
        @run.update!(
          status: "running",
          attempts: @run.attempts.to_i + 1,
          fence_version: fence,
          attempt_token: token,
          started_at: @run.started_at || @now,
          heartbeat_at: @now,
          recovery_enqueued_at: nil,
          available_at: nil
        )
        Attempt.new(token: token, fence_version: fence)
      end
    end

    def release_for_continuation!(reason:)
      checkpointed_at = current_time
      update_owned_run! do |current|
        metadata = current.metadata.to_h.merge("last_continuation_reason" => reason)
        current.update!(
          status: "queued",
          attempt_token: nil,
          heartbeat_at: checkpointed_at,
          last_checkpoint_at: checkpointed_at,
          available_at: checkpointed_at + CONTINUATION_DELAY,
          metadata: metadata
        )
      end
      telemetry("continuation_checkpointed", action: "continue", reason: reason)
    end

    def checkpoint_continuation!(result)
      checkpointed_at = current_time
      update_owned_run! do |current|
        progress = progress_for(current)
        current.update!(
          status: "queued",
          phase: progress.fetch(:phase),
          current_scope: progress[:current_scope],
          objects_total: progress.fetch(:objects_total),
          objects_completed: progress.fetch(:objects_completed),
          rows_total: progress.fetch(:rows_total),
          rows_completed: progress.fetch(:rows_completed),
          result: result.as_json,
          attempt_token: nil,
          heartbeat_at: checkpointed_at,
          last_checkpoint_at: checkpointed_at,
          available_at: checkpointed_at + CONTINUATION_DELAY,
          last_error_class: nil,
          last_error_message: nil
        )
      end
      telemetry("continuation_checkpointed", action: "continue")
    end

    def complete!(result)
      completed_at = current_time
      update_owned_run! do |current|
        progress = progress_for(current, final_result: result)
        current.update!(
          status: "completed",
          phase: "finalizing",
          current_scope: nil,
          objects_total: progress.fetch(:objects_total),
          objects_completed: progress.fetch(:objects_total),
          rows_total: progress.fetch(:rows_total),
          rows_completed: progress.fetch(:rows_total),
          result: result.as_json,
          attempt_token: nil,
          heartbeat_at: completed_at,
          last_checkpoint_at: completed_at,
          completed_at: completed_at,
          failed_at: nil,
          last_error_class: nil,
          last_error_message: nil
        )
      end
      telemetry("completed", action: "complete")
    end

    def failure_result(error)
      return { action: :fenced, status: @run.reload.status } unless owns_attempt?

      outcome = nil
      failed_at = current_time
      update_owned_run! do |current|
        metadata = current.metadata.to_h
        failure_count = metadata.fetch("failure_count", 0).to_i + 1
        metadata["failure_count"] = failure_count
        terminal = terminal_failure?(error) || failure_count >= max_failures
        wait = retry_wait(failure_count)
        current.update!(
          status: terminal ? "failed" : "retrying",
          attempt_token: nil,
          heartbeat_at: failed_at,
          available_at: (terminal ? nil : failed_at + wait),
          failed_at: (terminal ? failed_at : nil),
          last_error_at: failed_at,
          last_error_class: error.class.name,
          last_error_message: error.message,
          metadata: metadata
        )
        outcome = terminal ? { action: :failed, status: "failed" } : { action: :retry, status: "retrying", wait: wait }
      end
      telemetry(
        outcome.fetch(:action) == :failed ? "failed" : "retry_scheduled",
        action: outcome.fetch(:action).to_s,
        error_class: error.class.name,
        wait_seconds: outcome[:wait]&.to_i
      )
      outcome.merge(error: error)
    rescue LeaseLost
      { action: :fenced, status: @run.reload.status }
    end

    def update_owned_run!
      @run.with_lock do
        @run.reload
        unless @run.status == "running" &&
            @run.attempt_token == @attempt.token &&
            @run.fence_version == @attempt.fence_version
          raise LeaseLost
        end

        yield @run
      end
    end

    def owns_attempt?
      current = ProjectRetentionRun.find(@run.id)
      current.status == "running" &&
        current.attempt_token == @attempt&.token &&
        current.fence_version == @attempt&.fence_version
    end

    def progress_for(current, final_result: nil)
      archives = TelemetryArchive.where(project_retention_run_id: current.id)
      objects = TelemetryArchiveObject.where(telemetry_archive_id: archives.select(:id))
      objects_total = [ current.objects_total, objects.count ].max
      objects_completed = [ current.objects_completed, objects.verified.count ].max
      rows_total = [ current.rows_total, objects.sum(:expected_rows) ].max
      rows_completed = [
        current.rows_completed,
        objects.sum(:verified_rows),
        objects.where(source_cleanup_status: %w[completed blocked not_required]).sum(:expected_rows)
      ].max

      if final_result && rows_total.zero?
        candidate_rows = final_result.fetch(:candidates, {}).values.sum
        rows_total = candidate_rows
        rows_completed = candidate_rows
      end

      latest = archives.recent_first.first
      phase = if latest&.status == "verifying"
        "verifying"
      elsif latest&.status.in?(%w[pending uploading failed])
        "uploading"
      elsif archives.awaiting_source_cleanup.exists?
        "cleaning"
      else
        "finalizing"
      end

      {
        phase: phase,
        current_scope: latest&.scope,
        objects_total: objects_total,
        objects_completed: [ objects_completed, objects_total ].min,
        rows_total: rows_total,
        rows_completed: [ rows_completed, rows_total ].min
      }
    end

    def terminal_failure?(error)
      return true if error.is_a?(TelemetryArchiveInspector::VerificationError)
      return true if error.is_a?(ProjectRetentionRunner::SourceRetirementError)

      error.is_a?(TelemetryArchiveExporter::Error) && error.message.match?(
        /changed after|rows are missing|checksum mismatch|unsupported|predates immutable|still has .* eligible source rows/i
      )
    end

    def objects_per_attempt
      positive_integer_env("LOGISTER_RETENTION_OBJECTS_PER_ATTEMPT", DEFAULT_OBJECTS_PER_ATTEMPT)
    end

    def max_failures
      positive_integer_env("LOGISTER_RETENTION_MAX_FAILURES", DEFAULT_MAX_FAILURES)
    end

    def current_time
      @clock.call
    end

    def stale_after
      ProjectRetentionRun.stale_after
    end

    def retry_wait(failure_count)
      [ 2**failure_count, 5.minutes.to_i ].min.seconds + SecureRandom.random_number(5).seconds
    end

    def positive_integer_env(name, fallback)
      value = Integer(ENV.fetch(name, fallback))
      value.positive? ? value : fallback
    rescue ArgumentError, TypeError
      fallback
    end

    def telemetry(event, **details)
      ProjectRetentionRunTelemetry.emit(event: event, run: @run, at: Time.current, **details)
    end
  end
end
