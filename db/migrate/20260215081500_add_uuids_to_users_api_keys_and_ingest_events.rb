class AddUuidsToUsersApiKeysAndIngestEvents < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    add_uuid_column_with_backfill(:users)
    add_uuid_column_with_backfill(:api_keys)
    add_uuid_column_with_backfill(:ingest_events)
  end

  def down
    remove_uuid_column(:users)
    remove_uuid_column(:api_keys)
    remove_uuid_column(:ingest_events)
  end

  private

  def add_uuid_column_with_backfill(table)
    return if column_exists?(table, :uuid)

    add_column table, :uuid, :uuid, default: -> { "gen_random_uuid()" }
    execute "UPDATE #{table} SET uuid = gen_random_uuid() WHERE uuid IS NULL"
    change_column_null table, :uuid, false
    add_index table, :uuid, unique: true
  end

  def remove_uuid_column(table)
    return unless column_exists?(table, :uuid)

    remove_index table, :uuid if index_exists?(table, :uuid)
    remove_column table, :uuid
  end
end
