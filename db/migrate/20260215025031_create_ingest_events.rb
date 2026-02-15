class CreateIngestEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ingest_events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :api_key, null: false, foreign_key: true
      t.integer :event_type, null: false
      t.string :level
      t.text :message, null: false
      t.string :fingerprint
      t.jsonb :context, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :ingest_events, [ :project_id, :occurred_at ]
    add_index :ingest_events, [ :project_id, :event_type ]
  end
end
