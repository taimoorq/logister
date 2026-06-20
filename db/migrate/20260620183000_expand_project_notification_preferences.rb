class ExpandProjectNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    change_table :project_notification_preferences, bulk: true do |t|
      t.boolean :regression_enabled, null: false, default: true
      t.boolean :frequent_error_enabled, null: false, default: false
      t.integer :frequent_error_threshold_count, null: false, default: 25
      t.integer :frequent_error_window_minutes, null: false, default: 60
      t.boolean :milestone_alerts_enabled, null: false, default: false
      t.string :workflow_mode, null: false, default: "assigned_to_me"
      t.boolean :monitor_alerts_enabled, null: false, default: true
      t.boolean :project_spike_enabled, null: false, default: false
      t.integer :project_spike_threshold_count, null: false, default: 100
      t.integer :project_spike_window_minutes, null: false, default: 15
      t.boolean :performance_alerts_enabled, null: false, default: false
      t.integer :performance_p95_threshold_ms, null: false, default: 1_000
      t.boolean :release_notifications_enabled, null: false, default: false
      t.boolean :usage_notifications_enabled, null: false, default: true
      t.boolean :retention_notifications_enabled, null: false, default: true
      t.string :environment_filter, null: false, default: "all"
      t.string :severity_filter, null: false, default: "all"
      t.string :status_filter, null: false, default: "unresolved"
      t.integer :immediate_email_limit_per_hour, null: false, default: 10
      t.boolean :quiet_hours_enabled, null: false, default: false
      t.integer :quiet_hours_start, null: false, default: 22
      t.integer :quiet_hours_end, null: false, default: 7
    end

    add_index :project_notification_preferences,
              [ :project_id, :regression_enabled ],
              name: "idx_project_notification_preferences_regression"
    add_index :project_notification_preferences,
              [ :project_id, :monitor_alerts_enabled ],
              name: "idx_project_notification_preferences_monitors"
  end
end
