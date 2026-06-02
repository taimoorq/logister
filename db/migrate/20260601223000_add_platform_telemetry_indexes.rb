class AddPlatformTelemetryIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ingest_events,
              "project_id, (context->>'platform'), occurred_at DESC",
              name: "idx_ingest_events_project_platform_occurred",
              using: :btree,
              where: "COALESCE(context->>'platform', '') <> ''",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              "project_id, (context->>'service'), occurred_at DESC",
              name: "idx_ingest_events_project_service_occurred",
              using: :btree,
              where: "COALESCE(context->>'service', '') <> ''",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :ingest_events,
              "project_id, (context->>'deployment_id'), occurred_at DESC",
              name: "idx_ingest_events_cf_pages_deployment_occurred",
              using: :btree,
              where: "context->>'platform' = 'cloudflare_pages' AND COALESCE(context->>'deployment_id', '') <> ''",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :project_integration_settings,
              [ :provider, :enabled, :last_imported_at ],
              name: "idx_project_integrations_provider_enabled_imported",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
