class ExtendIngestEventsPartitions < ActiveRecord::Migration[8.1]
  PARENT_TABLES = %w[public.ingest_events public.ingest_events_partitioned].freeze
  PARTITION_PREFIX = "public.ingest_events_partitioned"
  FUTURE_MONTHS = 12

  def up
    partitioned_parent_tables.each do |parent_table|
      future_partition_months.each do |month|
        partition_name = "#{PARTITION_PREFIX}_#{month.strftime('%Y_%m')}"
        next if table_exists?(partition_name)

        execute <<~SQL
          CREATE TABLE IF NOT EXISTS #{partition_name}
          PARTITION OF #{parent_table}
          FOR VALUES FROM (#{quote(month.iso8601)}) TO (#{quote(month.next_month.iso8601)})
        SQL
      end
    end
  end

  def down
    # Keep partitions in place; dropping future partitions can remove data if the
    # migration is rolled back after those months have started receiving events.
  end

  private

  def partitioned_parent_tables
    PARENT_TABLES.select { |table_name| partitioned_table?(table_name) }
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

  def future_partition_months
    current_month = Time.current.utc.to_date.beginning_of_month
    (0..FUTURE_MONTHS).map { |offset| current_month.next_month(offset) }
  end
end
