class CreateNotificationEvaluations < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_evaluations do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :error_group, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :bucket, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :observation_count, null: false, default: 0
      t.integer :processing_observation_count, null: false, default: 0
      t.datetime :available_at, null: false
      t.datetime :last_observed_at
      t.datetime :started_at
      t.datetime :completed_at
      t.text :last_error
      t.timestamps
    end

    add_index :notification_evaluations,
      [ :kind, :error_group_id, :bucket ],
      unique: true,
      name: "index_notification_evaluations_on_logical_key"
    add_index :notification_evaluations, [ :status, :available_at ]

    add_check_constraint :notification_evaluations,
      "attempts >= 0 AND observation_count >= 0 AND processing_observation_count >= 0",
      name: "notification_evaluations_counts_nonnegative"
  end
end
