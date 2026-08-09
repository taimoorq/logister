class AddMobileEvidenceFiltersToProjectNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    change_table :project_notification_preferences, bulk: true do |t|
      t.string :mobile_source_filter, null: false, default: "all"
      t.string :mobile_diagnostic_kind_filter, null: false, default: "all"
      t.string :mobile_build_filter, null: false, default: "all"
      t.string :mobile_channel_filter, null: false, default: "all"
      t.string :mobile_artifact_state_filter, null: false, default: "all"
      t.string :late_arrival_policy, null: false, default: "notify_on_receipt"
    end
  end
end
