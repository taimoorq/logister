class CreateProjectIntegrationSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :project_integration_settings do |t|
      t.references :project, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :provider, null: false
      t.boolean :enabled, null: false, default: false
      t.string :account_id
      t.string :external_project_id
      t.string :external_project_name
      t.string :credential_reference
      t.datetime :last_imported_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index :uuid, unique: true
      t.index [ :project_id, :provider ], unique: true
      t.index [ :provider, :enabled ]
      t.index [ :enabled, :last_imported_at ]
    end
  end
end
