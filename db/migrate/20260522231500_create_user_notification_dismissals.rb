class CreateUserNotificationDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :user_notification_dismissals do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, null: false, foreign_key: true, index: true
      t.string :notification_key, null: false
      t.datetime :dismissed_at, null: false

      t.timestamps
    end

    add_index :user_notification_dismissals, :uuid, unique: true
    add_index :user_notification_dismissals,
              [ :user_id, :notification_key ],
              unique: true,
              name: "idx_user_notification_dismissals_uniqueness"
  end
end
