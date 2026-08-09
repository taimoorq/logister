class CreateNotificationIntents < ActiveRecord::Migration[8.1]
  def change
    add_column :check_in_monitors, :notification_state, :string
    add_column :check_in_monitors, :notification_transition_id, :uuid
    add_index :check_in_monitors, :notification_transition_id

    create_table :notification_intents do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :error_group, null: true, foreign_key: { on_delete: :cascade }
      t.references :check_in_monitor, null: true, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :dedup_key, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :metadata, null: false, default: {}
      t.integer :attempts, null: false, default: 0
      t.datetime :available_at, null: false
      t.datetime :started_at
      t.datetime :enqueued_at
      t.uuid :lease_token
      t.text :last_error
      t.timestamps
    end

    add_index :notification_intents, :dedup_key, unique: true
    add_index :notification_intents, [ :status, :available_at ]
    add_index :notification_intents, [ :status, :started_at ]
    add_index :notification_intents, [ :project_id, :created_at ]

    add_check_constraint :notification_intents,
      "status IN ('pending', 'processing', 'enqueued')",
      name: "notification_intents_status"
    add_check_constraint :notification_intents,
      "kind IN ('first_occurrence', 'regression', 'error_milestone', 'monitor_missed', 'monitor_recovered')",
      name: "notification_intents_kind"
    add_check_constraint :notification_intents,
      "attempts >= 0",
      name: "notification_intents_attempts_nonnegative"
    add_check_constraint :notification_intents,
      "(error_group_id IS NOT NULL) <> (check_in_monitor_id IS NOT NULL)",
      name: "notification_intents_exactly_one_subject"
    add_check_constraint :notification_intents,
      "(status = 'processing') = (lease_token IS NOT NULL AND started_at IS NOT NULL)",
      name: "notification_intents_processing_lease"
    add_check_constraint :notification_intents,
      "status <> 'enqueued' OR enqueued_at IS NOT NULL",
      name: "notification_intents_enqueued_at"
  end
end
