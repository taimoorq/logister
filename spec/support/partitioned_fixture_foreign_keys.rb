# frozen_string_literal: true

require "active_record/connection_adapters/postgresql_adapter"

# Rails 8.1's fixture validator checks information_schema.table_constraints,
# including PostgreSQL's generated per-partition foreign keys. Validating those
# individually incorrectly requires a referenced event to exist in every leaf.
# Validate the declared parent constraints; PostgreSQL checks their partitions.
# Keep this test-only workaround until Rails handles conparentid here:
# https://github.com/rails/rails/blob/v8.1.4/activerecord/lib/active_record/connection_adapters/postgresql/referential_integrity.rb
module PartitionedFixtureForeignKeys
  def check_all_foreign_keys_valid!
    transaction(requires_new: true) do
      execute(<<~SQL)
        DO $$
        DECLARE constraint_record record;
        BEGIN
          FOR constraint_record IN
            SELECT oid, conrelid::regclass AS table_name, conname
            FROM pg_catalog.pg_constraint
            WHERE contype = 'f' AND conparentid = 0
              AND connamespace IN (
                SELECT oid FROM pg_catalog.pg_namespace
                WHERE nspname = ANY (current_schemas(false))
              )
          LOOP
            UPDATE pg_catalog.pg_constraint SET convalidated = false
              WHERE oid = constraint_record.oid;
            EXECUTE format('ALTER TABLE %s VALIDATE CONSTRAINT %I',
              constraint_record.table_name, constraint_record.conname);
          END LOOP;
        END;
        $$;
      SQL
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(PartitionedFixtureForeignKeys)
