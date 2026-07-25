# frozen_string_literal: true

class AddMonitoringPausedAtToCheckInMonitors < ActiveRecord::Migration[8.0]
  def change
    add_column :check_in_monitors, :monitoring_paused_at, :datetime
  end
end
