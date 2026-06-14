# frozen_string_literal: true

module Logister
  class IngestEventsPartitioning
    class CutoverError < StandardError; end

    class SourceIngestEvent < ApplicationRecord
      self.table_name = "ingest_events"
      self.primary_key = :id
    end
    private_constant :SourceIngestEvent

    class PartitionedIngestEvent < ApplicationRecord
      self.table_name = "ingest_events_partitioned"
      self.primary_key = :id
    end
    private_constant :PartitionedIngestEvent

    DEFAULT_BATCH_SIZE = 10_000
    DEFAULT_FUTURE_PARTITION_MONTHS = 12
    SOURCE_TABLE = "public.ingest_events"
    SHADOW_TABLE = "public.ingest_events_partitioned"
    BACKUP_TABLE = "public.ingest_events_unpartitioned_backup"
    MIRROR_TRIGGER_NAME = "logister_ingest_events_partition_mirror"
    MIRROR_FUNCTION_NAME = "public.logister_mirror_ingest_event_to_partitioned"
    REFERENCE_CONSTRAINTS = [
      {
        table: "public.error_occurrences",
        old_name: "fk_rails_b004382b7c",
        new_name: "fk_error_occurrences_ingest_event_partition_ref",
        columns: %w[ingest_event_id ingest_event_occurred_at],
        null_guard: "ingest_event_id IS NOT NULL AND ingest_event_occurred_at IS NULL"
      },
      {
        table: "public.error_groups",
        old_name: "fk_rails_2d081e8402",
        new_name: "fk_error_groups_latest_event_partition_ref",
        columns: %w[latest_event_id latest_event_occurred_at],
        null_guard: "latest_event_id IS NOT NULL AND latest_event_occurred_at IS NULL"
      },
      {
        table: "public.check_in_monitors",
        old_name: "fk_rails_d3835f8871",
        new_name: "fk_check_in_monitors_last_event_partition_ref",
        columns: %w[last_event_id last_event_occurred_at],
        null_guard: "last_event_id IS NOT NULL AND last_event_occurred_at IS NULL"
      }
    ].freeze
    COLUMNS = %w[
      id
      api_key_id
      context
      created_at
      error_group_id
      event_type
      fingerprint
      level
      message
      occurred_at
      project_id
      updated_at
      uuid
    ].freeze
    UPDATE_COLUMNS = (COLUMNS - %w[id occurred_at]).freeze

    def initialize(connection: ActiveRecord::Base.connection)
      @connection = connection
    end

    def status
      return cutover_status unless table_exists?(SHADOW_TABLE)

      {
        phase: "pre_cutover",
        mirror_trigger_installed: mirror_trigger_installed?,
        source_events: count_rows(SOURCE_TABLE),
        shadow_events: count_rows(SHADOW_TABLE),
        missing_in_shadow: missing_count(source_table: SOURCE_TABLE, shadow_table: SHADOW_TABLE),
        extra_in_shadow: extra_count(source_table: SOURCE_TABLE, shadow_table: SHADOW_TABLE),
        mismatched_rows: mismatch_count(source_table: SOURCE_TABLE, shadow_table: SHADOW_TABLE),
        partitions: partitions
      }
    end

    def validate
      validate_tables(source_table: SOURCE_TABLE, shadow_table: SHADOW_TABLE)
    end

    def cutover_preflight
      validation = validate
      null_references = null_reference_counts
      checks = {
        source_table_exists: table_exists?(SOURCE_TABLE),
        shadow_table_exists: table_exists?(SHADOW_TABLE),
        backup_table_absent: !table_exists?(BACKUP_TABLE),
        source_is_unpartitioned: table_exists?(SOURCE_TABLE) && !partitioned_table?(SOURCE_TABLE),
        shadow_is_partitioned: table_exists?(SHADOW_TABLE) && partitioned_table?(SHADOW_TABLE),
        mirror_trigger_installed: mirror_trigger_installed?,
        validation_passed: validation.fetch(:valid),
        reference_timestamps_present: null_references.values.all?(&:zero?)
      }

      {
        ready: checks.values.all?,
        checks: checks,
        null_references: null_references,
        validation: validation,
        reference_constraints: reference_constraint_status
      }
    end

    def cutover(validate_before: true, lock_timeout: "30s")
      preflight = validate_before ? cutover_preflight : nil
      if preflight && !preflight.fetch(:ready)
        raise CutoverError, "Partition cutover preflight failed: #{preflight.fetch(:checks).inspect}"
      end

      started_at = monotonic_time

      connection.transaction do
        execute "SET LOCAL lock_timeout = #{connection.quote(lock_timeout)}" if lock_timeout.present?
        lock_cutover_tables
        drop_mirror_trigger
        drop_old_reference_constraints
        rename_cutover_tables
        reset_ingest_events_sequence
        add_composite_reference_constraints
      end

      clear_connection_caches

      {
        cutover_complete: true,
        elapsed_seconds: elapsed_seconds(started_at),
        preflight: preflight,
        status: cutover_status
      }
    end

    def validate_cutover_copy
      validate_tables(source_table: BACKUP_TABLE, shadow_table: SOURCE_TABLE)
    end

    def validate_cutover_constraints
      started_at = monotonic_time
      REFERENCE_CONSTRAINTS.each do |constraint|
        execute "ALTER TABLE #{constraint.fetch(:table)} VALIDATE CONSTRAINT #{constraint.fetch(:new_name)}"
      end

      {
        elapsed_seconds: elapsed_seconds(started_at),
        reference_constraints: reference_constraint_status
      }
    end

    def ensure_future_partitions(months_ahead: DEFAULT_FUTURE_PARTITION_MONTHS)
      months_ahead = Integer(months_ahead)
      created = []

      partition_maintenance_tables.each do |table_name|
        future_partition_months(months_ahead).each do |month|
          partition_name = monthly_partition_name(month)
          next if table_exists?(partition_name)

          create_monthly_partition(table_name, partition_name, month)
          created << { parent: table_name, partition: partition_name, month: month.strftime("%Y-%m") }
        end
      end

      {
        months_ahead: months_ahead,
        created_partitions: created,
        partitioned_tables: partition_maintenance_tables
      }
    end

    def backfill(from: nil, to: nil, batch_size: DEFAULT_BATCH_SIZE, dry_run: true)
      from = parse_time(from)
      to = parse_time(to)
      batch_size = normalized_batch_size(batch_size)

      result = {
        dry_run: dry_run,
        batch_size: batch_size,
        from: from&.utc&.iso8601,
        to: to&.utc&.iso8601,
        batches: 0,
        candidate_rows: 0,
        upserted_rows: 0
      }
      cursor = nil

      loop do
        batch = candidate_batch(from: from, to: to, cursor: cursor, limit: batch_size)
        break if batch.empty?

        result[:batches] += 1
        result[:candidate_rows] += batch.size
        result[:upserted_rows] += upsert_batch(batch) unless dry_run

        cursor = batch.last.fetch("id")
      end

      result
    end

    private

    attr_reader :connection

    def cutover_status
      {
        phase: partitioned_table?(SOURCE_TABLE) ? "post_cutover" : "unknown",
        ingest_events_partitioned: partitioned_table?(SOURCE_TABLE),
        backup_table_exists: table_exists?(BACKUP_TABLE),
        ingest_events: table_exists?(SOURCE_TABLE) ? count_rows(SOURCE_TABLE) : nil,
        backup_events: table_exists?(BACKUP_TABLE) ? count_rows(BACKUP_TABLE) : nil,
        old_shadow_table_exists: table_exists?(SHADOW_TABLE),
        mirror_trigger_installed: table_exists?(SOURCE_TABLE) && mirror_trigger_installed?,
        sequence_owner: sequence_owner,
        reference_constraints: reference_constraint_status,
        partitions: partitioned_table?(SOURCE_TABLE) ? partitions_for(SOURCE_TABLE) : []
      }
    end

    def validate_tables(source_table:, shadow_table:)
      missing = missing_count(source_table: source_table, shadow_table: shadow_table)
      extra = extra_count(source_table: source_table, shadow_table: shadow_table)
      mismatched = mismatch_count(source_table: source_table, shadow_table: shadow_table)
      months = month_counts(source_table: source_table, shadow_table: shadow_table)

      {
        valid: missing.zero? && extra.zero? && mismatched.zero? && months.all? { |month| month_counts_match?(month) },
        missing_in_shadow: missing,
        extra_in_shadow: extra,
        mismatched_rows: mismatched,
        months: months
      }
    end

    def mirror_trigger_installed?
      select_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_trigger
          WHERE tgname = #{connection.quote(MIRROR_TRIGGER_NAME)}
            AND tgrelid = #{connection.quote(SOURCE_TABLE)}::regclass
            AND NOT tgisinternal
        )
      SQL
    end

    def count_rows(table_name)
      select_value("SELECT COUNT(*) FROM #{table_name}").to_i
    end

    def missing_count(source_table:, shadow_table:)
      select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM #{source_table} source
        LEFT JOIN #{shadow_table} shadow
          ON shadow.id = source.id
         AND shadow.occurred_at = source.occurred_at
        WHERE shadow.id IS NULL
      SQL
    end

    def extra_count(source_table:, shadow_table:)
      select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM #{shadow_table} shadow
        LEFT JOIN #{source_table} source
          ON source.id = shadow.id
         AND source.occurred_at = shadow.occurred_at
        WHERE source.id IS NULL
      SQL
    end

    def mismatch_count(source_table:, shadow_table:)
      select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM #{source_table} source
        JOIN #{shadow_table} shadow
          ON shadow.id = source.id
         AND shadow.occurred_at = source.occurred_at
        WHERE #{mismatch_predicate}
      SQL
    end

    def mismatch_predicate
      UPDATE_COLUMNS.map do |column|
        "source.#{column} IS DISTINCT FROM shadow.#{column}"
      end.join(" OR ")
    end

    def partitions
      partitions_for(SHADOW_TABLE)
    end

    def partition_maintenance_tables
      [ SOURCE_TABLE, SHADOW_TABLE ].select { |table_name| partitioned_table?(table_name) }
    end

    def future_partition_months(months_ahead)
      current_month = Time.current.utc.to_date.beginning_of_month
      (0..months_ahead).map { |offset| current_month.next_month(offset) }
    end

    def monthly_partition_name(month)
      "public.ingest_events_partitioned_#{month.strftime('%Y_%m')}"
    end

    def create_monthly_partition(parent_table, partition_name, month)
      execute <<~SQL
        CREATE TABLE IF NOT EXISTS #{partition_name}
        PARTITION OF #{parent_table}
        FOR VALUES FROM (#{connection.quote(month.iso8601)}) TO (#{connection.quote(month.next_month.iso8601)})
      SQL
    end

    def partitions_for(table_name)
      connection.select_all(<<~SQL.squish).to_a
        SELECT relid::regclass::text AS name,
               parentrelid::regclass::text AS parent,
               isleaf,
               level
        FROM pg_partition_tree(#{connection.quote(table_name)}::regclass)
        ORDER BY level, name
      SQL
    end

    def month_counts(source_table:, shadow_table:)
      return month_counts_source_to_shadow if source_table == SOURCE_TABLE && shadow_table == SHADOW_TABLE
      return month_counts_backup_to_source if source_table == BACKUP_TABLE && shadow_table == SOURCE_TABLE

      raise ArgumentError, "Unsupported partition validation pair: #{source_table.inspect}, #{shadow_table.inspect}"
    end

    def month_counts_source_to_shadow
      connection.select_all(<<~SQL.squish).to_a
        WITH source_counts AS (
          SELECT date_trunc('month', occurred_at) AS month,
                 COUNT(*)::bigint AS event_count,
                 MIN(id)::bigint AS min_id,
                 MAX(id)::bigint AS max_id,
                 SUM(id)::numeric AS id_sum
          FROM public.ingest_events
          GROUP BY 1
        ),
        shadow_counts AS (
          SELECT date_trunc('month', occurred_at) AS month,
                 COUNT(*)::bigint AS event_count,
                 MIN(id)::bigint AS min_id,
                 MAX(id)::bigint AS max_id,
                 SUM(id)::numeric AS id_sum
          FROM public.ingest_events_partitioned
          GROUP BY 1
        )
        SELECT to_char(COALESCE(source_counts.month, shadow_counts.month), 'YYYY-MM') AS month,
               COALESCE(source_counts.event_count, 0)::bigint AS source_events,
               COALESCE(shadow_counts.event_count, 0)::bigint AS shadow_events,
               source_counts.min_id AS source_min_id,
               shadow_counts.min_id AS shadow_min_id,
               source_counts.max_id AS source_max_id,
               shadow_counts.max_id AS shadow_max_id,
               COALESCE(source_counts.id_sum, 0)::numeric::text AS source_id_sum,
               COALESCE(shadow_counts.id_sum, 0)::numeric::text AS shadow_id_sum
        FROM source_counts
        FULL OUTER JOIN shadow_counts
          ON shadow_counts.month = source_counts.month
        ORDER BY COALESCE(source_counts.month, shadow_counts.month)
      SQL
    end

    def month_counts_backup_to_source
      connection.select_all(<<~SQL.squish).to_a
        WITH source_counts AS (
          SELECT date_trunc('month', occurred_at) AS month,
                 COUNT(*)::bigint AS event_count,
                 MIN(id)::bigint AS min_id,
                 MAX(id)::bigint AS max_id,
                 SUM(id)::numeric AS id_sum
          FROM public.ingest_events_unpartitioned_backup
          GROUP BY 1
        ),
        shadow_counts AS (
          SELECT date_trunc('month', occurred_at) AS month,
                 COUNT(*)::bigint AS event_count,
                 MIN(id)::bigint AS min_id,
                 MAX(id)::bigint AS max_id,
                 SUM(id)::numeric AS id_sum
          FROM public.ingest_events
          GROUP BY 1
        )
        SELECT to_char(COALESCE(source_counts.month, shadow_counts.month), 'YYYY-MM') AS month,
               COALESCE(source_counts.event_count, 0)::bigint AS source_events,
               COALESCE(shadow_counts.event_count, 0)::bigint AS shadow_events,
               source_counts.min_id AS source_min_id,
               shadow_counts.min_id AS shadow_min_id,
               source_counts.max_id AS source_max_id,
               shadow_counts.max_id AS shadow_max_id,
               COALESCE(source_counts.id_sum, 0)::numeric::text AS source_id_sum,
               COALESCE(shadow_counts.id_sum, 0)::numeric::text AS shadow_id_sum
        FROM source_counts
        FULL OUTER JOIN shadow_counts
          ON shadow_counts.month = source_counts.month
        ORDER BY COALESCE(source_counts.month, shadow_counts.month)
      SQL
    end

    def table_exists?(table_name)
      select_value("SELECT to_regclass(#{connection.quote(table_name)}) IS NOT NULL")
    end

    def partitioned_table?(table_name)
      return false unless table_exists?(table_name)

      select_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_partitioned_table
          WHERE partrelid = #{connection.quote(table_name)}::regclass
        )
      SQL
    end

    def null_reference_counts
      REFERENCE_CONSTRAINTS.to_h do |constraint|
        [
          constraint.fetch(:new_name),
          select_value(<<~SQL.squish).to_i
            SELECT COUNT(*)
            FROM #{constraint.fetch(:table)}
            WHERE #{constraint.fetch(:null_guard)}
          SQL
        ]
      end
    end

    def reference_constraint_status
      REFERENCE_CONSTRAINTS.map do |constraint|
        {
          table: constraint.fetch(:table),
          old_name: constraint.fetch(:old_name),
          old_exists: constraint_exists?(constraint.fetch(:old_name)),
          new_name: constraint.fetch(:new_name),
          new_exists: constraint_exists?(constraint.fetch(:new_name)),
          new_validated: constraint_validated?(constraint.fetch(:new_name))
        }
      end
    end

    def lock_cutover_tables
      ([ SOURCE_TABLE, SHADOW_TABLE ] + REFERENCE_CONSTRAINTS.map { |constraint| constraint.fetch(:table) }).each do |table_name|
        execute "LOCK TABLE #{table_name} IN ACCESS EXCLUSIVE MODE"
      end
    end

    def drop_mirror_trigger
      execute "DROP TRIGGER IF EXISTS #{MIRROR_TRIGGER_NAME} ON #{SOURCE_TABLE}"
      execute "DROP FUNCTION IF EXISTS #{MIRROR_FUNCTION_NAME}()"
    end

    def drop_old_reference_constraints
      REFERENCE_CONSTRAINTS.each do |constraint|
        execute "ALTER TABLE #{constraint.fetch(:table)} DROP CONSTRAINT IF EXISTS #{constraint.fetch(:old_name)}"
      end
    end

    def rename_cutover_tables
      execute "ALTER TABLE #{SOURCE_TABLE} RENAME TO #{BACKUP_TABLE.split('.').last}"
      execute "ALTER TABLE #{SHADOW_TABLE} RENAME TO #{SOURCE_TABLE.split('.').last}"
    end

    def reset_ingest_events_sequence
      execute "ALTER TABLE #{BACKUP_TABLE} ALTER COLUMN id DROP DEFAULT"
      execute "ALTER TABLE #{SOURCE_TABLE} ALTER COLUMN id SET DEFAULT nextval('public.ingest_events_id_seq'::regclass)"
      execute "ALTER SEQUENCE public.ingest_events_id_seq OWNED BY #{SOURCE_TABLE}.id"
      execute <<~SQL.squish
        SELECT setval(
          'public.ingest_events_id_seq',
          COALESCE((SELECT MAX(id) FROM #{SOURCE_TABLE}), 1),
          EXISTS (SELECT 1 FROM #{SOURCE_TABLE})
        )
      SQL
    end

    def add_composite_reference_constraints
      REFERENCE_CONSTRAINTS.each do |constraint|
        source_id_column, source_timestamp_column = constraint.fetch(:columns)
        execute <<~SQL.squish
          ALTER TABLE #{constraint.fetch(:table)}
          ADD CONSTRAINT #{constraint.fetch(:new_name)}
          FOREIGN KEY (#{source_id_column}, #{source_timestamp_column})
          REFERENCES #{SOURCE_TABLE}(id, occurred_at)
          NOT VALID
        SQL
      end
    end

    def constraint_exists?(name)
      select_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = #{connection.quote(name)}
        )
      SQL
    end

    def constraint_validated?(name)
      select_value(<<~SQL.squish)
        SELECT COALESCE((
          SELECT convalidated
          FROM pg_constraint
          WHERE conname = #{connection.quote(name)}
        ), false)
      SQL
    end

    def sequence_owner
      select_value(<<~SQL.squish)
        SELECT pg_get_serial_sequence(#{connection.quote(SOURCE_TABLE)}, 'id')
      SQL
    end

    def month_counts_match?(month)
      month.fetch("source_events").to_i == month.fetch("shadow_events").to_i &&
        month["source_min_id"] == month["shadow_min_id"] &&
        month["source_max_id"] == month["shadow_max_id"] &&
        month.fetch("source_id_sum") == month.fetch("shadow_id_sum")
    end

    def candidate_batch(from:, to:, cursor:, limit:)
      # Use the source primary key. The old table has no global (occurred_at, id) index.
      event_table = SourceIngestEvent.arel_table
      relation = SourceIngestEvent.unscoped.order(id: :asc).limit(Integer(limit))
      relation = relation.where(event_table[:occurred_at].gteq(from)) if from
      relation = relation.where(event_table[:occurred_at].lt(to)) if to
      relation = relation.where(event_table[:id].gt(Integer(cursor))) if cursor

      relation.pluck(:id, :occurred_at).map do |id, occurred_at|
        { "id" => id, "occurred_at" => occurred_at }
      end
    end

    def upsert_batch(batch)
      ids = batch.map { |row| Integer(row.fetch("id")) }
      rows = SourceIngestEvent.unscoped.where(id: ids).pluck(*COLUMNS).map do |values|
        COLUMNS.zip(values).to_h
      end
      return 0 if rows.empty?

      PartitionedIngestEvent.upsert_all(rows, unique_by: :ingest_events_partitioned_id_occurred_at_key)
      rows.size
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      raise ArgumentError, "Invalid timestamp: #{value.inspect}"
    end

    def normalized_batch_size(value)
      Integer(value).positive? ? Integer(value) : DEFAULT_BATCH_SIZE
    rescue ArgumentError, TypeError
      DEFAULT_BATCH_SIZE
    end

    def select_value(sql)
      connection.select_value(sql)
    end

    def execute(sql)
      connection.execute(sql)
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_seconds(started_at)
      (monotonic_time - started_at).round(3)
    end

    def clear_connection_caches
      connection.clear_cache!
      connection.schema_cache.clear!
      IngestEvent.reset_column_information
    end
  end
end
