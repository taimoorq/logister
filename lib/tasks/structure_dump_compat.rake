namespace :db do
  namespace :schema do
    task :strip_incompatible_pg_dump_settings do
      structure_path = File.expand_path("../../db/structure.sql", __dir__)
      next unless File.exist?(structure_path)

      contents = File.read(structure_path)
      filtered = contents.lines.reject { |line| line == "SET transaction_timeout = 0;\n" }.join
      filtered.gsub!(
        /(ADD CONSTRAINT fk_ingest_events_partitioned_[^;]+) NOT VALID;/,
        "\\1;"
      )

      File.write(structure_path, filtered) if filtered != contents
    end
  end
end

Rake::Task["db:schema:dump"].enhance do
  Rake::Task["db:schema:strip_incompatible_pg_dump_settings"].invoke
end
