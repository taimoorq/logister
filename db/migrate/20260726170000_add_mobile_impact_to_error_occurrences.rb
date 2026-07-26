# frozen_string_literal: true

class AddMobileImpactToErrorOccurrences < ActiveRecord::Migration[8.1]
  def change
    change_table :error_occurrences, bulk: true do |table|
      table.string :mechanism
      table.string :release
      table.string :session_hash
      table.string :installation_hash
      table.string :user_hash
      table.boolean :foreground
      table.integer :telemetry_schema_version
      table.jsonb :dimensions, null: false, default: {}
    end

    add_index :error_occurrences, [ :error_group_id, :mechanism ]
    add_index :error_occurrences, [ :error_group_id, :release ]
    add_index :error_occurrences, [ :error_group_id, :installation_hash ]
    add_index :error_occurrences, [ :error_group_id, :session_hash ]
    add_index :error_occurrences, :dimensions, using: :gin
    add_index :error_occurrences, [ :error_group_id, :occurred_at, :id ], name: "idx_error_occurrences_cursor"

    change_table :error_groups, bulk: true do |table|
      table.integer :grouping_algorithm_version, null: false, default: 1
      table.jsonb :grouping_evidence, null: false, default: {}
    end
  end
end
