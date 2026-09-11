# frozen_string_literal: true

module Logister
  # One bounded preload per project/source type. Source identity includes the
  # canonical timestamp: IDs alone are not unique across event partitions.
  class TelemetryProjectionSources
    def initialize(deliveries)
      @projects = Project.where(id: deliveries.map(&:project_id).uniq).index_by(&:id)
      @records = {}
      deliveries.map(&:telemetry_outbox_event).uniq(&:id).group_by { |outbox| [ outbox.project_id, outbox.record_type ] }.each do |(project_id, type), outboxes|
        project = @projects[project_id]
        next unless project

        records = case type
        when "IngestEvent"
          IngestEvent.for_partition_references(outboxes, id_key: :record_id, occurred_at_key: :recorded_at)
            .where(project_id: project_id)
        when "TraceSpan"
          TraceSpan.where(project_id: project_id, id: outboxes.map(&:record_id))
        else
          []
        end
        records.each do |record|
          timestamp = type == "IngestEvent" ? record.occurred_at : record.started_at
          record.project = project
          @records[[ project_id, type, record.id, timestamp.to_r ]] = record
        end
      end
      deliveries.each do |delivery|
        delivery.project = @projects[delivery.project_id]
        delivery.telemetry_outbox_event.project = @projects[delivery.project_id]
      end
    end

    def project_for(delivery)
      @projects[delivery.project_id]
    end

    def fetch(delivery)
      outbox = delivery.telemetry_outbox_event
      @records[[ delivery.project_id, outbox.record_type, outbox.record_id, outbox.recorded_at.to_r ]]
    end
  end
end
