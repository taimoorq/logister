# frozen_string_literal: true

class AddUuidToCheckInMonitors < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BACKFILL_BATCH_SIZE = 1_000
  LOCK_TIMEOUT = "5s"
  STATEMENT_TIMEOUT = "30s"

  def up
    with_ddl_lock_timeout do
      add_column :check_in_monitors, :uuid, :uuid unless column_exists?(:check_in_monitors, :uuid)
      change_column_default :check_in_monitors, :uuid, from: nil, to: -> { "gen_random_uuid()" }
    end
    backfill_monitor_uuids
    ensure_concurrent_index!(
      :check_in_monitors,
      :uuid,
      name: "index_check_in_monitors_on_uuid",
      unique: true
    ) do
      add_index :check_in_monitors, :uuid, unique: true, algorithm: :concurrently
    end
    ensure_concurrent_index!(
      :check_in_monitors,
      [ :project_id, :updated_at, :uuid ],
      name: "idx_cli_monitors_project_updated_uuid",
      order: { updated_at: :desc, uuid: :desc }
    ) do
      add_index :check_in_monitors,
                [ :project_id, :updated_at, :uuid ],
                order: { updated_at: :desc, uuid: :desc },
                name: "idx_cli_monitors_project_updated_uuid",
                algorithm: :concurrently
    end
    ensure_concurrent_index!(
      :trace_spans,
      [ :project_id, :started_at, :uuid ],
      name: "idx_cli_root_traces_project_started_uuid",
      order: { started_at: :desc, uuid: :desc },
      where: "kind IN ('server', 'browser') AND (parent_span_id IS NULL OR parent_span_id = '')"
    ) do
      add_index :trace_spans,
                [ :project_id, :started_at, :uuid ],
                order: { started_at: :desc, uuid: :desc },
                where: "kind IN ('server', 'browser') AND (parent_span_id IS NULL OR parent_span_id = '')",
                name: "idx_cli_root_traces_project_started_uuid",
                algorithm: :concurrently
    end
    ensure_concurrent_index!(
      :project_deployments,
      "project_id, COALESCE(deployed_at, created_at) DESC, uuid DESC",
      name: "idx_cli_deployments_project_time_uuid"
    ) do
      execute <<~SQL.squish
        CREATE INDEX CONCURRENTLY idx_cli_deployments_project_time_uuid
        ON project_deployments (
          project_id,
          COALESCE(deployed_at, created_at) DESC,
          uuid DESC
        )
      SQL
    end
    with_ddl_lock_timeout do
      add_check_constraint :check_in_monitors, "uuid IS NOT NULL", name: "check_in_monitors_uuid_not_null", validate: false unless check_constraint_exists?(:check_in_monitors, name: "check_in_monitors_uuid_not_null")
    end
    with_validation_budgets do
      validate_check_constraint :check_in_monitors, name: "check_in_monitors_uuid_not_null"
    end
    with_ddl_lock_timeout do
      change_column_null :check_in_monitors, :uuid, false
      remove_check_constraint :check_in_monitors, name: "check_in_monitors_uuid_not_null"
    end
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_cli_deployments_project_time_uuid"
    remove_index :trace_spans, name: "idx_cli_root_traces_project_started_uuid", algorithm: :concurrently if index_exists?(:trace_spans, name: "idx_cli_root_traces_project_started_uuid")
    remove_index :check_in_monitors, name: "idx_cli_monitors_project_updated_uuid", algorithm: :concurrently if index_exists?(:check_in_monitors, name: "idx_cli_monitors_project_updated_uuid")

    # UUIDs are public monitor identities once this migration has served a CLI
    # response. Older application code tolerates the additive column, so a
    # rollback intentionally retains the UUID column, default, NOT NULL
    # constraint, and unique index instead of changing issued identities on a
    # later re-apply.
  end

  private

  def backfill_monitor_uuids
    loop do
      updated_ids = with_backfill_budgets do
        select_values(<<~SQL.squish)
          WITH batch AS MATERIALIZED (
            SELECT id
            FROM check_in_monitors
            WHERE uuid IS NULL
            ORDER BY id
            LIMIT #{BACKFILL_BATCH_SIZE}
          )
          UPDATE check_in_monitors AS monitors
          SET uuid = gen_random_uuid()
          FROM batch
          WHERE monitors.id = batch.id
            AND monitors.uuid IS NULL
          RETURNING monitors.id
        SQL
      end
      break if updated_ids.empty?
    end
  end

  def with_backfill_budgets(&block)
    with_local_timeouts(statement_timeout: STATEMENT_TIMEOUT, &block)
  end

  def with_validation_budgets(&block)
    with_local_timeouts(statement_timeout: "5min", &block)
  end

  def with_ddl_lock_timeout(&block)
    with_local_timeouts(statement_timeout: STATEMENT_TIMEOUT, &block)
  end

  def with_local_timeouts(statement_timeout:)
    connection.transaction(requires_new: true) do
      execute "SET LOCAL lock_timeout = #{quote(LOCK_TIMEOUT)}"
      execute "SET LOCAL statement_timeout = #{quote(statement_timeout)}"
      yield
    end
  end

  # CREATE INDEX CONCURRENTLY cannot run in a transaction, so scope the same
  # lock budget to the session and always restore the connection afterward.
  def with_concurrent_index_lock_timeout
    execute "SET lock_timeout = #{quote(LOCK_TIMEOUT)}"
    yield
  ensure
    execute "RESET lock_timeout"
  end

  def ensure_concurrent_index!(table, columns, name:, **definition)
    if index_present?(name)
      return if index_exists?(table, columns, name:, valid: true, **definition)
      if valid_index?(name)
        raise ActiveRecord::MigrationError, "#{name} exists with an incompatible definition"
      end

      drop_invalid_index_concurrently(name)
    end

    with_concurrent_index_lock_timeout { yield }
    return if index_exists?(table, columns, name:, valid: true, **definition)

    raise ActiveRecord::MigrationError, "#{name} was not created with the expected definition"
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
end
