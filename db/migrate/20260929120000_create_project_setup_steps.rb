# frozen_string_literal: true

# Stores only the decision that an optional setup step is not needed. Whether a
# step is complete is always derived from project evidence, never stored.
class CreateProjectSetupSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :project_setup_steps do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.string :status, null: false, default: "skipped"
      t.references :decided_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :project_setup_steps, [ :project_id, :key ], unique: true, name: "index_project_setup_steps_unique_key"
    add_check_constraint :project_setup_steps, "status = 'skipped'", name: "project_setup_steps_known_status"
  end
end
