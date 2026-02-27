class AddErrorGroupToIngestEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :ingest_events, :error_group, null: true, foreign_key: true, index: true
  end
end
