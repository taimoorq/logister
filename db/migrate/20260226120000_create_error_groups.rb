class CreateErrorGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :error_groups do |t|
      t.uuid   :uuid,             null: false, default: -> { "gen_random_uuid()" }
      t.references :project,      null: false, foreign_key: true, index: true
      t.references :latest_event, null: true,  foreign_key: { to_table: :ingest_events }, index: true

      # Identity — how we detect "same error"
      t.string  :fingerprint,       null: false
      t.string  :title,             null: false, default: ""
      t.string  :subtitle                         # exception class, controller, etc.
      t.string  :stage,             null: false, default: "production"
      t.string  :severity,          null: false, default: "error"

      # Lifecycle status
      # 0 = unresolved  (newly seen, open)
      # 1 = resolved    (marked fixed)
      # 2 = ignored     (user chose to ignore)
      # 3 = archived    (manually archived)
      t.integer :status,            null: false, default: 0

      # Counters & time-range
      t.integer  :occurrence_count, null: false, default: 0
      t.datetime :first_seen_at,    null: true
      t.datetime :last_seen_at,     null: true
      t.datetime :resolved_at,      null: true
      t.datetime :ignored_at,       null: true
      t.datetime :archived_at,      null: true

      # Re-open detection: if a "resolved" group gets a new occurrence,
      # we bump status back to unresolved and record when.
      t.integer  :reopen_count,     null: false, default: 0
      t.datetime :last_reopened_at, null: true

      t.timestamps
    end

    add_index :error_groups, :uuid,                    unique: true
    add_index :error_groups, [ :project_id, :fingerprint ], unique: true
    add_index :error_groups, [ :project_id, :status ]
    add_index :error_groups, [ :project_id, :last_seen_at ]
  end
end
