# frozen_string_literal: true

module Logister
  class ProjectPurgeRequest
    def initialize(project:, requested_by: nil, enqueue: true, now: Time.current)
      @project = project
      @requested_by = requested_by
      @enqueue = enqueue
      @now = now
    end

    def call
      purge = ProjectPurge.transaction do
        @project.lock!
        ledger = ProjectPurge.find_or_initialize_by(idempotency_key: idempotency_key)
        if ledger.new_record?
          ledger.assign_attributes(
            project: @project,
            source_project_id: @project.id,
            project_uuid: @project.uuid,
            project_name: @project.name,
            requested_by: @requested_by,
            requested_at: @now,
            status: "requested",
            configuration_snapshot: configuration_snapshot,
            audit_log: [ audit_entry("requested") ]
          )
          ledger.save!
        end

        tombstone_project!
        ensure_steps!(ledger)
        unless ledger.completed?
          ledger.update!(
            project: @project,
            status: "tombstoned",
            tombstoned_at: ledger.tombstoned_at || @now,
            failed_at: nil,
            last_error_class: nil,
            last_error_message: nil,
            last_error_at: nil,
            audit_log: Array(ledger.audit_log) + [ audit_entry("tombstoned") ]
          )
        end
        ledger
      end

      ProjectPurgeJob.perform_later(purge.id) if @enqueue && !purge.completed?
      purge
    end

    private

    def idempotency_key
      "project-purge/#{@project.uuid}"
    end

    def tombstone_project!
      @project.archive! unless @project.archived?
      @project.api_keys.active.update_all(revoked_at: @now, updated_at: @now)
      @project.update!(purge_requested_at: @project.purge_requested_at || @now)
    end

    def ensure_steps!(ledger)
      ProjectPurge::STORE_ORDER.each_with_index do |store_name, position|
        ledger.steps.find_or_create_by!(store_name: store_name) do |step|
          step.position = position
          step.status = "pending"
        end
      end
    end

    def configuration_snapshot
      config = Rails.configuration.x.logister
      TelemetryStoreGeneration.register_clickhouse!(config) if config.clickhouse_mode.to_s != "disabled"
      {
        "clickhouse" => {
          "mode" => (config.clickhouse_mode if config.respond_to?(:clickhouse_mode)),
          "database" => (config.clickhouse_database if config.respond_to?(:clickhouse_database)),
          "events_table" => (config.clickhouse_events_table if config.respond_to?(:clickhouse_events_table)),
          "spans_table" => (config.clickhouse_spans_table if config.respond_to?(:clickhouse_spans_table)),
          "automatic_purge_enabled" => ActiveModel::Type::Boolean.new.cast(
            ENV.fetch("LOGISTER_ENABLE_PROJECT_PURGE_CLICKHOUSE", "false")
          ),
          "generation_inventory_complete" => ActiveModel::Type::Boolean.new.cast(
            ENV.fetch("LOGISTER_ATTEST_CLICKHOUSE_GENERATION_INVENTORY_COMPLETE", "false")
          ),
          "never_used" => ActiveModel::Type::Boolean.new.cast(
            ENV.fetch("LOGISTER_ATTEST_CLICKHOUSE_NEVER_USED", "false")
          ),
          "generations" => TelemetryStoreGeneration.where(store_kind: "clickhouse").order(:first_seen_at).pluck(:locator)
        },
        "archive" => {
          "service" => InstanceConfiguration.value("archive_storage.service"),
          "prefix" => InstanceConfiguration.value("archive_storage.prefix"),
          "storage_locator" => InstanceConfiguration::ArchiveService.current_locator
        },
        "cache_store" => Rails.cache.class.name
      }
    end

    def audit_entry(event)
      {
        "event" => event,
        "at" => @now.utc.iso8601(6),
        "details" => {
          "project_id" => @project.id,
          "project_uuid" => @project.uuid,
          "requested_by_id" => @requested_by&.id
        }
      }
    end
  end
end
