class AddStageTrigramIndexToErrorGroups < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :error_groups, "LOWER(stage) gin_trgm_ops",
              using: :gin,
              name: "idx_error_groups_lower_stage_trgm",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
