# frozen_string_literal: true

class AddSelfMonitoringDestinationToInstallations < ActiveRecord::Migration[8.1]
  def change
    add_reference :installations,
                  :self_monitoring_project,
                  foreign_key: { to_table: :projects, on_delete: :nullify },
                  index: { unique: true }
    add_reference :installations,
                  :self_monitoring_api_key,
                  foreign_key: { to_table: :api_keys, on_delete: :nullify },
                  index: { unique: true }
  end
end
