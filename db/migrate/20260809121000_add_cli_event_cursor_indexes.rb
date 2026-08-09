# frozen_string_literal: true

class AddCliEventCursorIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLE = "public.ingest_events"
  LOCK_TIMEOUT = "5s"
  INDEXES = {
    "idx_ie_cli_occurred_uuid" => "USING btree (project_id, occurred_at DESC, uuid DESC)",
    "idx_ie_cli_created_uuid" => "USING btree (project_id, created_at ASC, uuid ASC)"
  }.freeze

  def up
    with_lock_timeout do
      INDEXES.each do |parent_index, definition|
        if partitioned_table?
          create_partitioned_index(parent_index, definition)
        else
          create_regular_index(TABLE, parent_index, definition)
        end
      end
    end
  end

  def down
    # These additive indexes are safe for the prior application version. Keep
    # them during application rollback: dropping a partitioned parent cascades
    # through every attached child under a blocking, non-concurrent lock and
    # discards resumable deployment work.
  end

  private

  # This migration is deliberately resumable. Bound every DDL lock wait for
  # parent creation, concurrent child creation/drop, and partition attachment;
  # a later deploy can retry from the valid indexes already completed.
  def with_lock_timeout
    execute "SET lock_timeout = #{quote(LOCK_TIMEOUT)}"
    yield
  ensure
    execute "RESET lock_timeout"
  end

  def create_partitioned_index(parent_index, definition)
    ensure_partitioned_parent_index!(parent_index, definition)
    partition_names.each do |partition|
      child_index = child_index_name(parent_index, partition)
      create_regular_index(partition, child_index, definition)
      next if index_attached?(parent_index, child_index)

      execute <<~SQL.squish
        ALTER INDEX public.#{parent_index}
        ATTACH PARTITION public.#{child_index}
      SQL
    end
    assert_partitioned_index_complete!(parent_index)
  end

  def create_regular_index(table, index, definition)
    if index_present?(index) && valid_index?(index)
      return if index_definition_compatible?(index, table:, definition:, only: false)

      raise ActiveRecord::MigrationError, "#{index} exists with an incompatible definition"
    end

    drop_invalid_index_concurrently(index)
    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS #{index}
      ON #{table} #{definition}
    SQL
    return if valid_index?(index) && index_definition_compatible?(index, table:, definition:, only: false)

    raise ActiveRecord::MigrationError, "#{index} was not created with the expected definition"
  end

  def partition_names
    select_values(<<~SQL.squish)
      SELECT relid::regclass::text
      FROM pg_partition_tree(#{quote(TABLE)}::regclass)
      WHERE relid <> #{quote(TABLE)}::regclass
        AND isleaf
      ORDER BY relid::regclass::text
    SQL
  end

  def child_index_name(parent_index, partition)
    suffix = partition.split(".").last.sub(/^ingest_events_partitioned_/, "").gsub(/[^a-zA-Z0-9_]/, "_")
    prefix = parent_index.include?("occurred") ? "idx_ie_cli_occ" : "idx_ie_cli_created"
    "#{prefix}_#{suffix.last(35)}"
  end

  def partitioned_table?
    select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1 FROM pg_partitioned_table
        WHERE partrelid = to_regclass(#{quote(TABLE)})
      )
    SQL
  end

  def index_attached?(parent_index, child_index)
    select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1 FROM pg_inherits
        WHERE inhparent = to_regclass(#{quote("public.#{parent_index}")})
          AND inhrelid = to_regclass(#{quote("public.#{child_index}")})
      )
    SQL
  end

  def attached_partition_indexes(parent_index)
    select_values(<<~SQL.squish)
      SELECT child.oid::regclass::text
      FROM pg_inherits inheritance
      JOIN pg_class child ON child.oid = inheritance.inhrelid
      WHERE inheritance.inhparent = to_regclass(#{quote("public.#{parent_index}")})
    SQL
  end

  # A partitioned parent created with ON ONLY is intentionally invalid until
  # every leaf index is attached. Preserve that compatible parent on retries so
  # PostgreSQL does not cascade-drop already-built children under a blocking
  # non-concurrent lock.
  def ensure_partitioned_parent_index!(index_name, definition)
    if index_present?(index_name)
      return if index_definition_compatible?(index_name, table: TABLE, definition:, only: true)

      raise ActiveRecord::MigrationError, "#{index_name} exists with an incompatible definition"
    end

    execute <<~SQL.squish
      CREATE INDEX #{index_name}
      ON ONLY #{TABLE} #{definition}
    SQL
    return if index_definition_compatible?(index_name, table: TABLE, definition:, only: true)

    raise ActiveRecord::MigrationError, "#{index_name} was not created with the expected definition"
  end

  def drop_invalid_index_concurrently(index_name)
    return unless index_present?(index_name)
    return if valid_index?(index_name)

    execute "DROP INDEX CONCURRENTLY public.#{index_name}"
  end

  def index_present?(index_name)
    select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1 FROM pg_class relation
        JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = 'public'
          AND relation.relkind IN ('i', 'I')
          AND relation.relname = #{quote(index_name)}
      )
    SQL
  end

  def valid_index?(index_name)
    select_value(<<~SQL.squish) == true
      SELECT COALESCE((
        SELECT metadata.indisvalid
        FROM pg_index metadata
        WHERE metadata.indexrelid = to_regclass(#{quote("public.#{index_name}")})
      ), false)
    SQL
  end

  def index_definition_compatible?(index_name, table:, definition:, only:)
    actual = select_value(<<~SQL.squish)
      SELECT pg_get_indexdef(to_regclass(#{quote("public.#{index_name}")}))
    SQL
    expected_table = table.include?(".") ? table : "public.#{table}"
    expected = "CREATE INDEX #{index_name} ON #{'ONLY ' if only}#{expected_table} #{definition}"
    normalize_index_definition(actual) == normalize_index_definition(expected)
  end

  def normalize_index_definition(definition)
    definition.to_s.gsub(/\s+ASC\b/i, "").squish
  end

  def assert_partitioned_index_complete!(parent_index)
    expected_children = partition_names.length
    attached_children = attached_partition_indexes(parent_index).length
    return if valid_index?(parent_index) && attached_children == expected_children

    raise ActiveRecord::MigrationError,
          "#{parent_index} is incomplete (#{attached_children}/#{expected_children} leaf indexes attached)"
  end
end
