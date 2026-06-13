module Logister
  class ProjectRetentionRunner
    DEFAULT_BATCH_SIZE = 1_000
    HOT_EVENT_TYPES = IngestEvent.event_types.keys.excluding("error").freeze

    def initialize(project:, policy: nil, batch_size: DEFAULT_BATCH_SIZE, storage_service: nil, dry_run: false, now: Time.current)
      @project = project
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      @storage_service = storage_service
      @dry_run = dry_run
      @policy = policy || default_policy
      @now = now
    end

    def call
      result = {
        project_id: @project.id,
        project_uuid: @project.uuid,
        dry_run: @dry_run,
        archive_enabled: @policy.archive_enabled?,
        archive_before_delete: @policy.archive_before_delete?,
        cutoffs: cutoffs.transform_values { |value| value&.utc&.iso8601 },
        archives: [],
        candidates: {},
        deleted: {}
      }

      result[:candidates][:hot_events] = hot_event_scope.count
      result[:candidates][:trace_spans] = trace_span_scope.count
      result[:candidates][:closed_error_groups] = closed_error_group_scope.count

      archive_retention_scope(result, :hot_events, "ingest_events", hot_cutoff, event_types: HOT_EVENT_TYPES)
      archive_retention_scope(result, :trace_spans, "trace_spans", trace_cutoff)
      archive_retention_scope(result, :error_events, "ingest_events", error_cutoff, event_types: [ "error" ]) if error_cutoff

      result[:deleted][:hot_events] = delete_events(hot_event_scope)
      result[:deleted][:trace_spans] = delete_trace_spans(trace_span_scope)
      result[:deleted][:closed_error_groups] = prune_closed_error_groups

      mark_policy_run!(result)
      result
    end

    private

    def default_policy
      return @project.retention_policy || @project.build_retention_policy if @dry_run

      ProjectRetentionPolicy.for(project: @project)
    end

    def cutoffs
      {
        hot_events: hot_cutoff,
        trace_spans: trace_cutoff,
        error_events: error_cutoff
      }
    end

    def hot_cutoff
      @hot_cutoff ||= @now - @policy.hot_retention_days.days
    end

    def trace_cutoff
      @trace_cutoff ||= @now - @policy.trace_retention_days.days
    end

    def error_cutoff
      return nil if @policy.error_retention_days.blank?

      @error_cutoff ||= @now - @policy.error_retention_days.days
    end

    def hot_event_scope
      @project.ingest_events
              .where("occurred_at < ?", hot_cutoff)
              .where(event_type: HOT_EVENT_TYPES.map { |event_type| IngestEvent.event_types.fetch(event_type) })
              .where(error_group_id: nil)
    end

    def trace_span_scope
      @project.trace_spans.where("started_at < ?", trace_cutoff)
    end

    def closed_error_group_scope
      return ErrorGroup.none unless error_cutoff

      @project.error_groups
              .where.not(status: ErrorGroup.statuses.fetch("unresolved"))
              .where("last_seen_at < ?", error_cutoff)
    end

    def archive_retention_scope(result, scope, record_type, before, event_types: nil)
      return unless @policy.archive_enabled? && @policy.archive_before_delete?
      return unless before

      after = last_completed_archive_before(scope)
      return if after && after >= before

      archive_result = TelemetryArchiveExporter.new(
        record_type: record_type,
        project: @project,
        before: before,
        after: after,
        event_types: event_types,
        batch_size: @batch_size,
        storage_service: @storage_service,
        dry_run: @dry_run
      ).call

      archive_summary = archive_result.merge(scope: scope)
      result[:archives] << archive_summary
      if !@dry_run && archive_result.fetch(:rows).positive?
        record_archive!(scope, archive_result, before, after)
        @policy.update!(last_archive_run_at: @now)
      end
    rescue TelemetryArchiveExporter::Error => e
      record_archive_failure!(scope, record_type, before, after, e) unless @dry_run
      raise
    end

    def last_completed_archive_before(scope)
      @project.telemetry_archives.completed.where(scope: scope.to_s).maximum(:before_at)
    end

    def record_archive!(scope, archive_result, before, after)
      objects = archive_result.fetch(:objects)
      @project.telemetry_archives.create!(
        scope: scope.to_s,
        record_type: archive_result.fetch(:record_type),
        status: "completed",
        before_at: before,
        after_at: after,
        rows: archive_result.fetch(:rows),
        bytes: objects.sum { |object| object.fetch(:bytes).to_i },
        objects: objects,
        dry_run: false
      )
    end

    def record_archive_failure!(scope, record_type, before, after, error)
      @project.telemetry_archives.create!(
        scope: scope.to_s,
        record_type: record_type,
        status: "failed",
        before_at: before,
        after_at: after,
        rows: 0,
        bytes: 0,
        objects: [],
        dry_run: false,
        error_message: "#{error.class}: #{error.message}"
      )
    end

    def delete_events(scope)
      return 0 if @dry_run

      deleted = 0
      scope.in_batches(of: @batch_size) do |batch|
        references = batch.pluck(:id, :occurred_at).map do |id, occurred_at|
          { id: id, occurred_at: occurred_at }
        end
        ids = references.pluck(:id)
        clear_event_references(ids)
        deleted += IngestEvent.for_partition_references(references, id_key: :id, occurred_at_key: :occurred_at).delete_all
      end
      deleted
    end

    def delete_trace_spans(scope)
      return 0 if @dry_run

      deleted = 0
      scope.in_batches(of: @batch_size) do |batch|
        deleted += batch.delete_all
      end
      deleted
    end

    def prune_closed_error_groups
      scope = closed_error_group_scope
      return 0 if @dry_run

      deleted = 0
      scope.find_each(batch_size: @batch_size) do |group|
        event_references = (
          group.error_occurrences.pluck(:ingest_event_id, :ingest_event_occurred_at) +
          IngestEvent.where(error_group_id: group.id).pluck(:id, :occurred_at)
        ).uniq
        IngestEvent.where(error_group_id: group.id).update_all(error_group_id: nil, updated_at: @now)
        group.destroy!
        delete_events_by_references(event_references)
        deleted += 1
      end
      deleted
    end

    def delete_events_by_references(references)
      event_references = Array(references).filter_map do |id, occurred_at|
        next if id.blank?

        { id: id, occurred_at: occurred_at }
      end
      event_ids = event_references.pluck(:id)
      return 0 if event_ids.empty?

      clear_event_references(event_ids)
      ErrorOccurrence.where(ingest_event_id: event_ids).delete_all
      IngestEvent.for_partition_references(event_references, id_key: :id, occurred_at_key: :occurred_at)
                 .where(project_id: @project.id)
                 .delete_all
    end

    def clear_event_references(ids)
      event_ids = Array(ids).compact
      return if event_ids.empty?

      CheckInMonitor.where(last_event_id: event_ids).update_all(last_event_id: nil, last_event_occurred_at: nil, updated_at: @now)
      ErrorGroup.where(latest_event_id: event_ids).update_all(latest_event_id: nil, latest_event_occurred_at: nil, updated_at: @now)
    end

    def mark_policy_run!(result)
      return if @dry_run

      @policy.update!(
        last_retention_run_at: @now,
        last_retention_result: result.as_json
      )
    end
  end
end
