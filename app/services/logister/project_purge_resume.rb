# frozen_string_literal: true

module Logister
  class ProjectPurgeResume
    class NotAuthorized < StandardError; end

    def initialize(project_purge:, actor:, enqueue: true, now: Time.current)
      @project_purge = project_purge
      @actor = actor
      @enqueue = enqueue
      @now = now
    end

    def call
      authorize!
      return @project_purge if @project_purge.completed?

      @project_purge.with_lock do
        snapshot = refreshed_configuration_snapshot
        @project_purge.update!(
          status: "tombstoned",
          configuration_snapshot: snapshot,
          failed_at: nil,
          last_error_at: nil,
          last_error_class: nil,
          last_error_message: nil
        )
      end
      @project_purge.append_audit!(
        "resume_requested",
        {
          "actor_id" => @actor.id,
          "previous_step" => @project_purge.current_step,
          "clickhouse_generation_inventory_complete" => @project_purge.configuration_snapshot
            .dig("clickhouse", "generation_inventory_complete")
        },
        at: @now
      )
      ProjectPurgeJob.perform_later(@project_purge.id) if @enqueue
      @project_purge
    end

    private

    def refreshed_configuration_snapshot
      snapshot = @project_purge.configuration_snapshot.deep_dup
      clickhouse = snapshot["clickhouse"] ||= {}
      if truthy_env?("LOGISTER_ATTEST_CLICKHOUSE_GENERATION_INVENTORY_COMPLETE")
        clickhouse["generation_inventory_complete"] = true
        registered = TelemetryStoreGeneration.where(store_kind: "clickhouse").order(:first_seen_at).pluck(:locator)
        clickhouse["generations"] = (Array(clickhouse["generations"]) + registered)
          .uniq { |locator| locator["generation_id"] }
      end
      if truthy_env?("LOGISTER_ATTEST_CLICKHOUSE_NEVER_USED") && Array(clickhouse["generations"]).empty?
        clickhouse["never_used"] = true
      end
      snapshot
    end

    def truthy_env?(key)
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(key, "false"))
    end

    def authorize!
      owner_id = @project_purge.project&.user_id
      allowed = @actor&.application_admin? || @actor&.id == owner_id || @actor&.id == @project_purge.requested_by_id
      raise NotAuthorized, "Not authorized to resume this project purge" unless allowed
    end
  end
end
