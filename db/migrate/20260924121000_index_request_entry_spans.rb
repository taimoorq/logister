class IndexRequestEntrySpans < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :trace_spans, [ :project_id, :started_at, :uuid ],
      order: { started_at: :desc, uuid: :desc }, where: "kind IN ('server', 'browser')",
      name: "idx_request_entries_project_started_uuid", algorithm: :concurrently, if_not_exists: true
  end
end
