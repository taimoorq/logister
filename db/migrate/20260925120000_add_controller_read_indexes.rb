# frozen_string_literal: true

class AddControllerReadIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEXES = {
    "idx_error_occurrences_group_received" => [ :error_occurrences, "error_group_id, created_at DESC, id DESC", nil ],
    "idx_cli_entry_traces_project_millis_uuid" => [ :trace_spans, "project_id, date_trunc('milliseconds', started_at) DESC, uuid DESC", "kind IN ('server', 'browser')" ],
    "idx_deployments_lane_recency" => [ :project_deployments, "project_id, repository_full_name, environment, COALESCE(deployed_at, updated_at) DESC, id DESC", "deployed_at IS NOT NULL" ],
    "idx_deployments_lane_undated" => [ :project_deployments, "project_id, repository_full_name, environment, COALESCE(deployed_at, updated_at) DESC, id DESC", "deployed_at IS NULL" ],
    "idx_apple_symbols_project_created" => [ :apple_symbol_artifacts, "project_id, created_at DESC, id DESC", nil ],
    "idx_users_created_cursor" => [ :users, "created_at DESC, id DESC", nil ]
  }.freeze

  def up
    with_bounded_ddl do
      INDEXES.each do |name, (table, columns, predicate)|
        valid = select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = to_regclass(#{quote("public.#{name}")})")
        next if valid

        # Retry interrupted concurrent builds rather than accepting invalid indexes.
        remove_index table, name: name, algorithm: :concurrently unless valid.nil?
        execute "CREATE INDEX CONCURRENTLY #{quote_column_name(name)} ON #{quote_table_name(table)} (#{columns})#{" WHERE #{predicate}" if predicate}"
      end
    end
  end

  def down
    with_bounded_ddl do
      INDEXES.each do |name, (table, _columns, _predicate)|
        remove_index table, name: name, algorithm: :concurrently, if_exists: true
      end
    end
  end

  private

  def with_bounded_ddl
    original_lock_timeout = select_value("SHOW lock_timeout")
    original_statement_timeout = select_value("SHOW statement_timeout")
    execute "SET lock_timeout = '5s'"
    execute "SET statement_timeout = '5min'"
    yield
  ensure
    execute "SET lock_timeout = #{quote(original_lock_timeout)}" if original_lock_timeout
    execute "SET statement_timeout = #{quote(original_statement_timeout)}" if original_statement_timeout
  end
end
