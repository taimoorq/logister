class AddMobileHealthNotificationsToProjectNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    add_column :project_notification_preferences, :mobile_health_notifications_enabled, :boolean, null: false, default: false
  end
end
