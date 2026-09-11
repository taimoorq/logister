# frozen_string_literal: true

class AddOrderedActiveDeliveryIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  ACTIVE = "status IN ('pending', 'retrying', 'processing') AND attempts < 8"
  INDEXES = {
    "idx_telemetry_deliveries_active_order" => [ [ :available_at, :id ], ACTIVE ],
    "idx_telemetry_deliveries_active_group" => [ [ :project_id, :destination, :available_at, :id ], "#{ACTIVE} AND batch_key IS NULL" ]
  }.freeze

  def up
    with_bounded_ddl do
      INDEXES.each do |name, (columns, predicate)|
        valid = select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = to_regclass(#{quote("public.#{name}")})")
        next if valid

        # A cancelled concurrent build leaves an invalid index. Remove only
        # this migration's residue before retrying; IF NOT EXISTS would skip it.
        remove_index :telemetry_deliveries, name: name, algorithm: :concurrently unless valid.nil?
        add_index :telemetry_deliveries, columns, name: name, where: predicate, algorithm: :concurrently
      end
    end
  end

  def down
    with_bounded_ddl do
      INDEXES.each_key do |name|
        remove_index :telemetry_deliveries, name: name, algorithm: :concurrently, if_exists: true
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
