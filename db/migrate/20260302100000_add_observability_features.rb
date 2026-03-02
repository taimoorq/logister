class AddObservabilityFeatures < ActiveRecord::Migration[8.1]
  def change
    add_column :error_groups, :introduced_in_release, :string
    add_column :error_groups, :last_seen_release, :string
    add_column :error_groups, :resolved_in_release, :string
    add_column :error_groups, :regressed_in_release, :string
    add_column :error_groups, :regression_count, :integer, null: false, default: 0

    add_index :error_groups, [ :project_id, :introduced_in_release ]
    add_index :error_groups, [ :project_id, :regressed_in_release ]

    create_table :check_in_monitors do |t|
      t.references :project, null: false, foreign_key: true
      t.references :last_event, null: true, foreign_key: { to_table: :ingest_events }
      t.string :slug, null: false
      t.string :environment, null: false, default: "production"
      t.integer :expected_interval_seconds, null: false, default: 300
      t.datetime :last_check_in_at
      t.string :last_status, null: false, default: "ok"
      t.datetime :last_error_at
      t.integer :consecutive_missed_count, null: false, default: 0
      t.timestamps
    end

    add_index :check_in_monitors, [ :project_id, :slug, :environment ], unique: true, name: "idx_check_in_monitors_uniqueness"
  end
end
