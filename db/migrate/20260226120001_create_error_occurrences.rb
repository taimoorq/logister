class CreateErrorOccurrences < ActiveRecord::Migration[8.1]
  def change
    create_table :error_occurrences do |t|
      t.uuid       :uuid,            null: false, default: -> { "gen_random_uuid()" }
      t.references :error_group,     null: false, foreign_key: true, index: true
      t.references :ingest_event,    null: false, foreign_key: true, index: true
      t.datetime   :occurred_at,     null: false

      t.timestamps
    end

    add_index :error_occurrences, :uuid,                       unique: true
    add_index :error_occurrences, [ :error_group_id, :occurred_at ]
    # Prevent the same ingest_event being linked twice to the same group
    add_index :error_occurrences, [ :error_group_id, :ingest_event_id ], unique: true
  end
end
