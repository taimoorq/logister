# frozen_string_literal: true

module Logister
  module ProjectPurgeAdapters
    class Postgresql
      BATCH_SIZE = 1_000

      def initialize(project_purge:, batch_size: BATCH_SIZE)
        @project_purge = project_purge
        @batch_size = batch_size.to_i.positive? ? batch_size.to_i : BATCH_SIZE
      end

      def call
        project = Project.find_by(id: @project_purge.source_project_id)
        return { status: "completed", project_deleted: true, already_absent: true } unless project

        unless project.archived? && project.purge_pending?
          raise "Project must be archived and tombstoned before PostgreSQL purge"
        end

        counts = source_counts(project)
        remove_error_workflow_rows!(project)
        deleted_events = delete_partitioned_events!(project)
        deleted_spans = delete_trace_spans!(project)
        project.reload.destroy_for_purge!

        if Project.exists?(id: @project_purge.source_project_id)
          raise "Project still exists after PostgreSQL deletion"
        end

        {
          status: "completed",
          project_deleted: true,
          source_counts: counts,
          deleted_ingest_events: deleted_events,
          deleted_trace_spans: deleted_spans,
          verified_project_absent: true
        }
      end

      private

      def source_counts(project)
        {
          "ingest_events" => project.ingest_events.count,
          "trace_spans" => project.trace_spans.count,
          "error_groups" => project.error_groups.count,
          "telemetry_archives" => project.telemetry_archives.count,
          "telemetry_idempotency_keys" => TelemetryIdempotencyKey.where(project_id: project.id).count,
          "telemetry_outbox_events" => TelemetryOutboxEvent.where(project_id: project.id).count,
          "telemetry_deliveries_by_status" => TelemetryDelivery.where(project_id: project.id).group(:status).count
        }
      end

      def remove_error_workflow_rows!(project)
        now = Time.current
        CheckInMonitor.where(project_id: project.id).update_all(
          last_event_id: nil,
          last_event_occurred_at: nil,
          updated_at: now
        )
        group_ids = ErrorGroup.where(project_id: project.id).select(:id)
        IngestEvent.where(project_id: project.id).where.not(error_group_id: nil)
          .update_all(error_group_id: nil, updated_at: now)
        ErrorOccurrence.where(error_group_id: group_ids).delete_all
        EmailNotificationDelivery.where(error_group_id: group_ids).update_all(error_group_id: nil, updated_at: now)
        ErrorGroupExternalLink.where(project_id: project.id).delete_all
        ErrorGroup.where(project_id: project.id).delete_all
      end

      def delete_partitioned_events!(project)
        deleted = 0
        project.ingest_events.in_batches(of: @batch_size) do |batch|
          references = batch.pluck(:id, :occurred_at).map do |id, occurred_at|
            { id: id, occurred_at: occurred_at }
          end
          references.each_slice(IngestEvent::PARTITION_REFERENCE_BATCH_SIZE) do |reference_batch|
            deleted += IngestEvent.for_partition_references(
              reference_batch,
              id_key: :id,
              occurred_at_key: :occurred_at
            ).where(project_id: project.id).delete_all
          end
        end
        deleted
      end

      def delete_trace_spans!(project)
        deleted = 0
        project.trace_spans.in_batches(of: @batch_size) { |batch| deleted += batch.delete_all }
        deleted
      end
    end
  end
end
