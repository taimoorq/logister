class AddIntegrationKindToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :integration_kind, :string, null: false, default: "ruby"
    add_index :projects, :integration_kind
  end
end
