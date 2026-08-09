# frozen_string_literal: true

class AlignTelemetrySourceIdentityScope < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INGEST_TABLE = "public.ingest_events"
  INGEST_INDEX = "idx_ingest_events_project_uuid"
  TRACE_SCOPED_INDEX = "idx_trace_spans_project_uuid"
  TRACE_GLOBAL_INDEX = "index_trace_spans_on_uuid"

  def up
    add_ledger_acceptance_state
    add_trace_span_project_identity
    add_ingest_event_project_identity_lookup
  end

  def down
    restore_trace_span_global_identity
    remove_ingest_event_project_identity_lookup
    remove_index :telemetry_idempotency_keys,
                 name: "idx_telemetry_keys_source_retired",
                 algorithm: :concurrently if index_name_exists?(:telemetry_idempotency_keys, "idx_telemetry_keys_source_retired")
    remove_column :telemetry_idempotency_keys, :source_retired_at if column_exists?(:telemetry_idempotency_keys, :source_retired_at)
    remove_column :telemetry_idempotency_keys, :acceptance_metadata if column_exists?(:telemetry_idempotency_keys, :acceptance_metadata)
  end

  private

  def add_ledger_acceptance_state
    add_column :telemetry_idempotency_keys,
               :acceptance_metadata,
               :jsonb,
               null: false,
               default: {} unless column_exists?(:telemetry_idempotency_keys, :acceptance_metadata)
    add_column :telemetry_idempotency_keys,
               :source_retired_at,
               :datetime unless column_exists?(:telemetry_idempotency_keys, :source_retired_at)
    retired_index = "idx_telemetry_keys_source_retired"
    drop_invalid_index_concurrently(retired_index)
    add_index :telemetry_idempotency_keys,
              [ :project_id, :source_retired_at ],
              name: retired_index,
              where: "source_retired_at IS NOT NULL",
              algorithm: :concurrently unless index_name_exists?(:telemetry_idempotency_keys, retired_index)
  end

  def add_trace_span_project_identity
    drop_invalid_index_concurrently(TRACE_SCOPED_INDEX)
    execute <<~SQL.squish
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS #{TRACE_SCOPED_INDEX}
      ON public.trace_spans (project_id, uuid)
    SQL
    execute "DROP INDEX CONCURRENTLY IF EXISTS public.#{TRACE_GLOBAL_INDEX}"
  end

  def restore_trace_span_global_identity
    duplicate = select_value(<<~SQL.squish)
      SELECT uuid::text
      FROM public.trace_spans
      GROUP BY uuid
      HAVING COUNT(*) > 1
      LIMIT 1
    SQL
    if duplicate.present?
      raise ActiveRecord::IrreversibleMigration,
            "trace span UUID #{duplicate} is now used by multiple projects"
    end

    drop_invalid_index_concurrently(TRACE_GLOBAL_INDEX)
    execute <<~SQL.squish
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS #{TRACE_GLOBAL_INDEX}
      ON public.trace_spans (uuid)
    SQL
    execute "DROP INDEX CONCURRENTLY IF EXISTS public.#{TRACE_SCOPED_INDEX}"
  end

  def add_ingest_event_project_identity_lookup
    # A unique index on (project_id, uuid) is not legal on this range-partitioned
    # table because PostgreSQL requires every partition key (occurred_at) in a
    # partitioned unique constraint. The idempotency ledger and advisory lock are
    # the canonical uniqueness boundary; this index makes legacy-source lookups
    # tenant-selective without implying a guarantee PostgreSQL cannot provide.
    if partitioned_table?(INGEST_TABLE)
      execute <<~SQL.squish
        CREATE INDEX IF NOT EXISTS #{INGEST_INDEX}
        ON ONLY #{INGEST_TABLE} (project_id, uuid)
      SQL
      partition_names.each do |partition_name|
        child_index = ingest_child_index_name(partition_name)
        drop_invalid_index_concurrently(child_index)
        execute <<~SQL.squish
          CREATE INDEX CONCURRENTLY IF NOT EXISTS #{child_index}
          ON #{partition_name} (project_id, uuid)
        SQL
        attach_ingest_partition_index(child_index)
      end
    else
      execute <<~SQL.squish
        CREATE INDEX CONCURRENTLY IF NOT EXISTS #{INGEST_INDEX}
        ON #{INGEST_TABLE} (project_id, uuid)
      SQL
    end
  end

  def remove_ingest_event_project_identity_lookup
    if partitioned_table?(INGEST_TABLE)
      child_indexes = attached_partition_indexes(INGEST_INDEX)
      child_indexes |= partition_names.map do |partition_name|
        "public.#{ingest_child_index_name(partition_name)}"
      end
      execute "DROP INDEX IF EXISTS public.#{INGEST_INDEX}"
      child_indexes.each do |index_name|
        execute "DROP INDEX CONCURRENTLY IF EXISTS #{quote_table_name(index_name)}"
      end
    else
      execute "DROP INDEX CONCURRENTLY IF EXISTS public.#{INGEST_INDEX}"
    end
  end

  def attach_ingest_partition_index(child_index)
    return if index_attached?(INGEST_INDEX, child_index)

    execute <<~SQL.squish
      ALTER INDEX public.#{INGEST_INDEX}
      ATTACH PARTITION public.#{child_index}
    SQL
  end

  def partition_names
    select_values(<<~SQL.squish)
      SELECT relid::regclass::text
      FROM pg_partition_tree(#{quote(INGEST_TABLE)}::regclass)
      WHERE relid <> #{quote(INGEST_TABLE)}::regclass
        AND isleaf
      ORDER BY relid::regclass::text
    SQL
  end

  def ingest_child_index_name(partition_name)
    suffix = partition_name.split(".").last.sub(/^ingest_events_partitioned_/, "")
    suffix = suffix.gsub(/[^a-zA-Z0-9_]/, "_")
    "idx_ie_project_uuid_#{suffix.last(38)}"
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

  def index_attached?(parent_index, child_index)
    select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1
        FROM pg_inherits
        WHERE inhparent = to_regclass(#{quote("public.#{parent_index}")})
          AND inhrelid = to_regclass(#{quote("public.#{child_index}")})
      )
    SQL
  end

  def attached_partition_indexes(parent_index)
    select_values(<<~SQL.squish)
      SELECT child_index.oid::regclass::text
      FROM pg_inherits inheritance
      JOIN pg_class child_index ON child_index.oid = inheritance.inhrelid
      WHERE inheritance.inhparent = to_regclass(#{quote("public.#{parent_index}")})
      ORDER BY child_index.oid::regclass::text
    SQL
  end

  def drop_invalid_index_concurrently(index_name)
    return unless index_name_exists_by_catalog?(index_name)
    return if index_valid?(index_name)

    execute "DROP INDEX CONCURRENTLY public.#{index_name}"
  end

  def index_name_exists_by_catalog?(index_name)
    select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1
        FROM pg_class index_relation
        JOIN pg_namespace namespace ON namespace.oid = index_relation.relnamespace
        WHERE namespace.nspname = 'public'
          AND index_relation.relkind IN ('i', 'I')
          AND index_relation.relname = #{quote(index_name)}
      )
    SQL
  end

  def index_valid?(index_name)
    select_value(<<~SQL.squish)
      SELECT index_metadata.indisvalid
      FROM pg_index index_metadata
      WHERE index_metadata.indexrelid = to_regclass(#{quote("public.#{index_name}")})
    SQL
  end
end
