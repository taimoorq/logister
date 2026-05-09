class CreateProjectNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :project_notification_preferences do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :project, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.boolean :first_occurrence_enabled, null: false, default: true
      t.string :digest_frequency, null: false, default: "none"
      t.integer :digest_send_hour, null: false, default: 9
      t.string :time_zone, null: false, default: "UTC"
      t.boolean :send_empty_digest, null: false, default: false

      t.timestamps
    end

    add_index :project_notification_preferences, :uuid, unique: true
    add_index :project_notification_preferences,
      [ :project_id, :user_id ],
      unique: true,
      name: "idx_project_notification_preferences_uniqueness"
    add_index :project_notification_preferences,
      [ :digest_frequency, :digest_send_hour ],
      name: "idx_project_notification_preferences_digest_due"
  end
end
