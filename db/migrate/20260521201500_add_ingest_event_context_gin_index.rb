class AddIngestEventContextGinIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ingest_events,
              :context,
              name: "idx_ingest_events_context_path_ops",
              using: :gin,
              opclass: :jsonb_path_ops,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
