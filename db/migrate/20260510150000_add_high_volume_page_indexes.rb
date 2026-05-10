class AddHighVolumePageIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :ingest_events, [ :project_id, :updated_at ],
              order: { updated_at: :desc },
              name: "idx_ingest_events_project_updated_at",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :error_groups, [ :project_id, :status, :last_seen_at ],
              order: { last_seen_at: :desc },
              name: "idx_error_groups_project_status_last_seen",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :error_groups, [ :project_id, :status, :first_seen_at ],
              order: { first_seen_at: :desc },
              name: "idx_error_groups_project_status_first_seen",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :error_groups, [ :project_id, :updated_at ],
              order: { updated_at: :desc },
              name: "idx_error_groups_project_updated_at",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :api_keys, [ :project_id, :updated_at ],
              order: { updated_at: :desc },
              name: "idx_api_keys_project_updated_at",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :check_in_monitors, [ :project_id, :updated_at ],
              order: { updated_at: :desc },
              name: "idx_check_in_monitors_project_updated_at",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :error_groups, "LOWER(title) gin_trgm_ops",
              using: :gin,
              name: "idx_error_groups_lower_title_trgm",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :error_groups, "LOWER(COALESCE(subtitle, '')) gin_trgm_ops",
              using: :gin,
              name: "idx_error_groups_lower_subtitle_trgm",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :error_groups, "LOWER(fingerprint) gin_trgm_ops",
              using: :gin,
              name: "idx_error_groups_lower_fingerprint_trgm",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
