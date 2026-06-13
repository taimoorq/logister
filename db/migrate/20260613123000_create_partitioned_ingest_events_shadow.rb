class CreatePartitionedIngestEventsShadow < ActiveRecord::Migration[8.1]
  TABLE_NAME = "ingest_events_partitioned"
  DEFAULT_FUTURE_MONTHS = 6

  def up
    create_shadow_table
    create_partitions
    add_shadow_constraints
    add_shadow_indexes
  end

  def down
    execute "DROP TABLE IF EXISTS public.#{TABLE_NAME} CASCADE"
  end

  private

  def create_shadow_table
    execute <<~SQL
      CREATE TABLE IF NOT EXISTS public.#{TABLE_NAME} (
        id bigint DEFAULT nextval('public.ingest_events_id_seq'::regclass) NOT NULL,
        api_key_id bigint NOT NULL,
        context jsonb DEFAULT '{}'::jsonb NOT NULL,
        created_at timestamp(6) without time zone NOT NULL,
        error_group_id bigint,
        event_type integer NOT NULL,
        fingerprint character varying,
        level character varying,
        message text NOT NULL,
        occurred_at timestamp(6) without time zone NOT NULL,
        project_id bigint NOT NULL,
        updated_at timestamp(6) without time zone NOT NULL,
        uuid uuid DEFAULT gen_random_uuid() NOT NULL
      )
      PARTITION BY RANGE (occurred_at)
    SQL
  end

  def create_partitions
    partition_months.each do |month|
      create_month_partition(month)
    end

    execute <<~SQL
      CREATE TABLE IF NOT EXISTS public.#{TABLE_NAME}_default
      PARTITION OF public.#{TABLE_NAME}
      DEFAULT
    SQL
  end

  def partition_months
    first_month = earliest_event_month || Time.current.utc.to_date.beginning_of_month
    last_month = (Time.current.utc.to_date + DEFAULT_FUTURE_MONTHS.months).beginning_of_month

    months = []
    month = first_month
    while month <= last_month
      months << month
      month = month.next_month
    end
    months
  end

  def earliest_event_month
    value = select_value("SELECT MIN(occurred_at) FROM public.ingest_events")
    return if value.blank?

    Time.zone.parse(value.to_s).to_date.beginning_of_month
  end

  def create_month_partition(month)
    from = month.iso8601
    to = month.next_month.iso8601
    suffix = month.strftime("%Y_%m")

    execute <<~SQL
      CREATE TABLE IF NOT EXISTS public.#{TABLE_NAME}_#{suffix}
      PARTITION OF public.#{TABLE_NAME}
      FOR VALUES FROM (#{quote(from)}) TO (#{quote(to)})
    SQL
  end

  def add_shadow_constraints
    add_unique_constraint(
      "ingest_events_partitioned_id_occurred_at_key",
      "UNIQUE (id, occurred_at)"
    )
    add_foreign_key_constraint(
      "fk_ingest_events_partitioned_api_keys",
      "FOREIGN KEY (api_key_id) REFERENCES public.api_keys(id)"
    )
    add_foreign_key_constraint(
      "fk_ingest_events_partitioned_error_groups",
      "FOREIGN KEY (error_group_id) REFERENCES public.error_groups(id)"
    )
    add_foreign_key_constraint(
      "fk_ingest_events_partitioned_projects",
      "FOREIGN KEY (project_id) REFERENCES public.projects(id)"
    )
  end

  def add_shadow_indexes
    create_index "idx_ingest_events_part_activity_env_cursor",
                 "USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0)"
    create_index "idx_ingest_events_part_activity_release_cursor",
                 "USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text))"
    create_index "idx_ingest_events_part_cf_pages_deployment",
                 "USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text))"
    create_index "idx_ingest_events_part_context_path_ops",
                 "USING gin (context jsonb_path_ops)"
    create_index "idx_ingest_events_part_activity_cursor",
                 "USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0)"
    create_index "idx_ingest_events_part_activity_occurred",
                 "USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0)"
    create_index "idx_ingest_events_part_db_query_occurred",
                 "USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text))"
    create_index "idx_ingest_events_part_environment_occurred",
                 "USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC)"
    create_index "idx_ingest_events_part_metric_message",
                 "USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1)"
    create_index "idx_ingest_events_part_occurred_type",
                 "USING btree (project_id, event_type, occurred_at DESC)"
    create_index "idx_ingest_events_part_platform_occurred",
                 "USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text)"
    create_index "idx_ingest_events_part_release_occurred",
                 "USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text)"
    create_index "idx_ingest_events_part_service_occurred",
                 "USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text)"
    create_index "idx_ingest_events_part_transactions",
                 "USING btree (project_id, occurred_at DESC) WHERE (event_type = 2)"
    create_index "idx_ingest_events_part_type_retention",
                 "USING btree (project_id, event_type, occurred_at, id)"
    create_index "idx_ingest_events_part_updated_at",
                 "USING btree (project_id, updated_at DESC)"
    create_index "idx_ingest_events_part_retention_created",
                 "USING btree (created_at, id)"
    create_index "index_ingest_events_part_api_key_id",
                 "USING btree (api_key_id)"
    create_index "index_ingest_events_part_error_group_id",
                 "USING btree (error_group_id)"
    create_index "index_ingest_events_part_project_id",
                 "USING btree (project_id)"
    create_index "index_ingest_events_part_project_type",
                 "USING btree (project_id, event_type)"
    create_index "index_ingest_events_part_project_occurred",
                 "USING btree (project_id, occurred_at)"
    create_index "index_ingest_events_part_uuid",
                 "USING btree (uuid)"
  end

  def add_unique_constraint(name, definition)
    return if constraint_exists?(name)

    execute "ALTER TABLE public.#{TABLE_NAME} ADD CONSTRAINT #{name} #{definition}"
  end

  def add_foreign_key_constraint(name, definition)
    return if constraint_exists?(name)

    execute "ALTER TABLE public.#{TABLE_NAME} ADD CONSTRAINT #{name} #{definition}"
  end

  def constraint_exists?(name)
    select_value(<<~SQL.squish).present?
      SELECT 1
      FROM pg_constraint
      WHERE conname = #{quote(name)}
    SQL
  end

  def create_index(name, definition)
    return if index_name_exists?(name)

    execute "CREATE INDEX #{name} ON public.#{TABLE_NAME} #{definition}"
  end

  def index_name_exists?(name)
    select_value(<<~SQL.squish).present?
      SELECT 1
      FROM pg_class
      WHERE relkind = 'I'
        AND relname = #{quote(name)}
    SQL
  end
end
