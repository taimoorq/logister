class CreateEmailNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :email_notification_deliveries do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :project, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.references :error_group, null: true, foreign_key: true, index: true
      t.string :notification_kind, null: false
      t.string :dedup_key, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :period_start_at
      t.datetime :period_end_at
      t.datetime :sent_at
      t.text :last_error
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :email_notification_deliveries, :uuid, unique: true
    add_index :email_notification_deliveries, :dedup_key, unique: true
    add_index :email_notification_deliveries,
      [ :user_id, :project_id, :notification_kind, :period_start_at ],
      name: "idx_email_deliveries_digest_lookup"
    add_index :email_notification_deliveries,
      [ :status, :created_at ],
      name: "idx_email_deliveries_status_created_at"
  end
end
