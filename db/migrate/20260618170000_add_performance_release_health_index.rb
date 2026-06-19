class AddPerformanceReleaseHealthIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TARGET_TABLES = {
    "public.ingest_events" => "idx_ingest_events_release_health_occurred",
    "public.ingest_events_partitioned" => "idx_ingest_events_part_release_health_occurred"
  }.freeze

  INDEX_DEFINITION = <<~SQL.squish
    USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text)))
    WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text)
  SQL

  def up
    TARGET_TABLES.each do |table_name, index_name|
      next unless table_exists?(table_name)

      if partitioned_table?(table_name)
        create_partitioned_index(table_name, index_name)
      else
        create_regular_index(table_name, index_name)
      end
    end
  end

  def down
    TARGET_TABLES.each do |table_name, index_name|
      next unless table_exists?(table_name)

      if partitioned_table?(table_name)
        execute "DROP INDEX IF EXISTS #{qualified_index_name(index_name)}"
        partition_names(table_name).each do |partition_name|
          execute "DROP INDEX CONCURRENTLY IF EXISTS #{qualified_index_name(partition_index_name(index_name, partition_name))}"
        end
      else
        execute "DROP INDEX CONCURRENTLY IF EXISTS #{qualified_index_name(index_name)}"
      end
    end
  end

  private

  def create_regular_index(table_name, index_name)
    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS #{quote_column_name(index_name)}
      ON #{table_name} #{INDEX_DEFINITION}
    SQL
  end

  def create_partitioned_index(table_name, index_name)
    execute <<~SQL.squish
      CREATE INDEX IF NOT EXISTS #{quote_column_name(index_name)}
      ON ONLY #{table_name} #{INDEX_DEFINITION}
    SQL

    partition_names(table_name).each do |partition_name|
      child_index_name = partition_index_name(index_name, partition_name)
      create_regular_index(partition_name, child_index_name)
      attach_partition_index(index_name, child_index_name)
    end
  end

  def attach_partition_index(parent_index_name, child_index_name)
    return if index_attached?(parent_index_name, child_index_name)

    execute <<~SQL.squish
      ALTER INDEX #{qualified_index_name(parent_index_name)}
      ATTACH PARTITION #{qualified_index_name(child_index_name)}
    SQL
  end

  def partition_names(table_name)
    select_values(<<~SQL.squish)
      SELECT relid::regclass::text
      FROM pg_partition_tree(#{quote(table_name)}::regclass)
      WHERE relid <> #{quote(table_name)}::regclass
        AND isleaf
      ORDER BY relid::regclass::text
    SQL
  end

  def partition_index_name(parent_index_name, partition_name)
    suffix = partition_name.split(".").last.sub(/^ingest_events_partitioned_/, "")
    suffix = suffix.gsub(/[^a-zA-Z0-9_]/, "_")
    prefix = parent_index_name.include?("_part_") ? "idx_iep_release_health" : "idx_ie_release_health"

    "#{prefix}_#{suffix.last(36)}"
  end

  def index_attached?(parent_index_name, child_index_name)
    select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1
        FROM pg_inherits
        WHERE inhparent = to_regclass(#{quote("public.#{parent_index_name}")})
          AND inhrelid = to_regclass(#{quote("public.#{child_index_name}")})
      )
    SQL
  end

  def partitioned_table?(table_name)
    select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1
        FROM pg_partitioned_table
        WHERE partrelid = to_regclass(#{quote(table_name)})
      )
    SQL
  end

  def table_exists?(table_name)
    select_value("SELECT to_regclass(#{quote(table_name)}) IS NOT NULL")
  end

  def qualified_index_name(index_name)
    "public.#{quote_column_name(index_name)}"
  end
end
