# frozen_string_literal: true

class CreateCliDeviceAuthorizations < ActiveRecord::Migration[8.0]
  def change
    create_table :cli_device_authorizations do |t|
      t.uuid :uuid, null: false, default: "gen_random_uuid()"
      t.string :device_code_digest, null: false
      t.string :user_code_digest, null: false
      t.string :user_code_display, null: false
      t.string :client_name, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :requested_scopes, null: false, default: []
      t.boolean :approved_all_projects, null: false, default: false
      t.jsonb :approved_project_ids, null: false, default: []
      t.references :user, foreign_key: true
      t.references :cli_access_token, foreign_key: true
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.datetime :denied_at
      t.datetime :consumed_at
      t.datetime :last_polled_at
      t.timestamps
    end

    add_index :cli_device_authorizations, :uuid, unique: true
    add_index :cli_device_authorizations, :device_code_digest, unique: true
    add_index :cli_device_authorizations, :user_code_digest, unique: true
    add_index :cli_device_authorizations, [ :status, :expires_at ]
  end
end
