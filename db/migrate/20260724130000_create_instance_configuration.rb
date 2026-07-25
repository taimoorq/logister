# frozen_string_literal: true

class CreateInstanceConfiguration < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :application_admin, :boolean, default: false, null: false

    create_table :installations do |t|
      t.string :singleton_key, null: false, default: "primary"
      t.references :claimed_by_user, foreign_key: { to_table: :users }, null: true
      t.datetime :claimed_at
      t.datetime :completed_at
      t.integer :setup_version, null: false, default: 1
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :installations, :singleton_key, unique: true

    create_table :installation_steps do |t|
      t.references :installation, null: false, foreign_key: true
      t.string :key, null: false
      t.string :status, null: false, default: "pending"
      t.string :configuration_fingerprint
      t.datetime :last_verified_at
      t.references :last_verified_by_user, foreign_key: { to_table: :users }, null: true
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :installation_steps, [ :installation_id, :key ], unique: true

    create_table :instance_settings do |t|
      t.string :key, null: false
      t.text :encrypted_value, null: false
      t.references :updated_by_user, foreign_key: { to_table: :users }, null: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :instance_settings, :key, unique: true

    create_table :instance_setting_changes do |t|
      t.string :key, null: false
      t.string :action, null: false
      t.string :source, null: false, default: "admin_ui"
      t.references :actor, foreign_key: { to_table: :users }, null: true
      t.string :request_id
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :instance_setting_changes, [ :key, :created_at ]
  end
end
