class AddUuidToProjects < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    add_column :projects, :uuid, :uuid, default: -> { "gen_random_uuid()" }
    execute "UPDATE projects SET uuid = gen_random_uuid() WHERE uuid IS NULL"
    change_column_null :projects, :uuid, false
    add_index :projects, :uuid, unique: true
  end

  def down
    remove_index :projects, :uuid
    remove_column :projects, :uuid
  end
end
