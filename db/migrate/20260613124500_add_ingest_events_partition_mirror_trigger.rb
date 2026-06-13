class AddIngestEventsPartitionMirrorTrigger < ActiveRecord::Migration[8.1]
  FUNCTION_NAME = "public.logister_mirror_ingest_event_to_partitioned"
  TRIGGER_NAME = "logister_ingest_events_partition_mirror"

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION #{FUNCTION_NAME}()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          DELETE FROM public.ingest_events_partitioned
          WHERE id = OLD.id
            AND occurred_at = OLD.occurred_at;

          RETURN OLD;
        END IF;

        IF TG_OP = 'UPDATE'
           AND (OLD.id IS DISTINCT FROM NEW.id
                OR OLD.occurred_at IS DISTINCT FROM NEW.occurred_at) THEN
          DELETE FROM public.ingest_events_partitioned
          WHERE id = OLD.id
            AND occurred_at = OLD.occurred_at;
        END IF;

        INSERT INTO public.ingest_events_partitioned (
          id,
          api_key_id,
          context,
          created_at,
          error_group_id,
          event_type,
          fingerprint,
          level,
          message,
          occurred_at,
          project_id,
          updated_at,
          uuid
        )
        VALUES (
          NEW.id,
          NEW.api_key_id,
          NEW.context,
          NEW.created_at,
          NEW.error_group_id,
          NEW.event_type,
          NEW.fingerprint,
          NEW.level,
          NEW.message,
          NEW.occurred_at,
          NEW.project_id,
          NEW.updated_at,
          NEW.uuid
        )
        ON CONFLICT (id, occurred_at) DO UPDATE
        SET api_key_id = EXCLUDED.api_key_id,
            context = EXCLUDED.context,
            created_at = EXCLUDED.created_at,
            error_group_id = EXCLUDED.error_group_id,
            event_type = EXCLUDED.event_type,
            fingerprint = EXCLUDED.fingerprint,
            level = EXCLUDED.level,
            message = EXCLUDED.message,
            project_id = EXCLUDED.project_id,
            updated_at = EXCLUDED.updated_at,
            uuid = EXCLUDED.uuid;

        RETURN NEW;
      END;
      $$;
    SQL

    execute <<~SQL
      DROP TRIGGER IF EXISTS #{TRIGGER_NAME} ON public.ingest_events;

      CREATE TRIGGER #{TRIGGER_NAME}
      AFTER INSERT OR UPDATE OR DELETE ON public.ingest_events
      FOR EACH ROW
      EXECUTE FUNCTION #{FUNCTION_NAME}();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS #{TRIGGER_NAME} ON public.ingest_events"
    execute "DROP FUNCTION IF EXISTS #{FUNCTION_NAME}()"
  end
end
