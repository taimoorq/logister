SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: logister_mirror_ingest_event_to_partitioned(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logister_mirror_ingest_event_to_partitioned() RETURNS trigger
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_keys (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    last_used_at timestamp(6) without time zone,
    name character varying NOT NULL,
    project_id bigint NOT NULL,
    revoked_at timestamp(6) without time zone,
    token_digest character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: api_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_keys_id_seq OWNED BY public.api_keys.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: check_in_monitors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.check_in_monitors (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    last_event_id bigint,
    slug character varying NOT NULL,
    environment character varying DEFAULT 'production'::character varying NOT NULL,
    expected_interval_seconds integer DEFAULT 300 NOT NULL,
    last_check_in_at timestamp(6) without time zone,
    last_status character varying DEFAULT 'ok'::character varying NOT NULL,
    last_error_at timestamp(6) without time zone,
    consecutive_missed_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    last_event_occurred_at timestamp(6) without time zone
);


--
-- Name: check_in_monitors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.check_in_monitors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: check_in_monitors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.check_in_monitors_id_seq OWNED BY public.check_in_monitors.id;


--
-- Name: cli_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cli_access_tokens (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id bigint NOT NULL,
    name character varying NOT NULL,
    token_digest character varying NOT NULL,
    scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    allowed_project_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    all_projects boolean DEFAULT false NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: cli_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cli_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cli_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cli_access_tokens_id_seq OWNED BY public.cli_access_tokens.id;


--
-- Name: cli_device_authorizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cli_device_authorizations (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    device_code_digest character varying NOT NULL,
    user_code_digest character varying NOT NULL,
    user_code_display character varying NOT NULL,
    client_name character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    requested_scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    approved_all_projects boolean DEFAULT false NOT NULL,
    approved_project_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    user_id bigint,
    cli_access_token_id bigint,
    expires_at timestamp(6) without time zone NOT NULL,
    approved_at timestamp(6) without time zone,
    denied_at timestamp(6) without time zone,
    consumed_at timestamp(6) without time zone,
    last_polled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: cli_device_authorizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cli_device_authorizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cli_device_authorizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cli_device_authorizations_id_seq OWNED BY public.cli_device_authorizations.id;


--
-- Name: email_notification_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_notification_deliveries (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id bigint NOT NULL,
    user_id bigint NOT NULL,
    error_group_id bigint,
    notification_kind character varying NOT NULL,
    dedup_key character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    period_start_at timestamp(6) without time zone,
    period_end_at timestamp(6) without time zone,
    sent_at timestamp(6) without time zone,
    last_error text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: email_notification_deliveries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.email_notification_deliveries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_notification_deliveries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.email_notification_deliveries_id_seq OWNED BY public.email_notification_deliveries.id;


--
-- Name: error_group_external_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_group_external_links (
    id bigint NOT NULL,
    uuid character varying NOT NULL,
    project_id bigint NOT NULL,
    error_group_id bigint NOT NULL,
    created_by_id bigint,
    provider character varying DEFAULT 'github'::character varying NOT NULL,
    link_type character varying DEFAULT 'issue'::character varying NOT NULL,
    url character varying NOT NULL,
    title character varying,
    repository_full_name character varying,
    external_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: error_group_external_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.error_group_external_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: error_group_external_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.error_group_external_links_id_seq OWNED BY public.error_group_external_links.id;


--
-- Name: error_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_groups (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id bigint NOT NULL,
    latest_event_id bigint,
    fingerprint character varying NOT NULL,
    title character varying DEFAULT ''::character varying NOT NULL,
    subtitle character varying,
    stage character varying DEFAULT 'production'::character varying NOT NULL,
    severity character varying DEFAULT 'error'::character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    occurrence_count integer DEFAULT 0 NOT NULL,
    first_seen_at timestamp(6) without time zone,
    last_seen_at timestamp(6) without time zone,
    resolved_at timestamp(6) without time zone,
    ignored_at timestamp(6) without time zone,
    archived_at timestamp(6) without time zone,
    reopen_count integer DEFAULT 0 NOT NULL,
    last_reopened_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    introduced_in_release character varying,
    last_seen_release character varying,
    resolved_in_release character varying,
    regressed_in_release character varying,
    regression_count integer DEFAULT 0 NOT NULL,
    assigned_user_id bigint,
    assigned_by_user_id bigint,
    assigned_at timestamp(6) without time zone,
    latest_event_occurred_at timestamp(6) without time zone
);


--
-- Name: error_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.error_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: error_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.error_groups_id_seq OWNED BY public.error_groups.id;


--
-- Name: error_occurrences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_occurrences (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    error_group_id bigint NOT NULL,
    ingest_event_id bigint NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ingest_event_occurred_at timestamp(6) without time zone
);


--
-- Name: error_occurrences_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.error_occurrences_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: error_occurrences_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.error_occurrences_id_seq OWNED BY public.error_occurrences.id;


--
-- Name: github_installations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_installations (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    installation_id bigint NOT NULL,
    account_login character varying NOT NULL,
    account_type character varying,
    repository_selection character varying,
    active boolean DEFAULT true NOT NULL,
    suspended_at timestamp(6) without time zone,
    installed_by_id bigint,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    events jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: github_installations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.github_installations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: github_installations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.github_installations_id_seq OWNED BY public.github_installations.id;


--
-- Name: github_repositories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_repositories (
    id bigint NOT NULL,
    github_installation_id bigint NOT NULL,
    external_id bigint NOT NULL,
    full_name character varying NOT NULL,
    owner_name character varying NOT NULL,
    repo_name character varying NOT NULL,
    default_branch character varying,
    html_url character varying,
    private boolean DEFAULT true NOT NULL,
    archived boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_synced_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: github_repositories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.github_repositories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: github_repositories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.github_repositories_id_seq OWNED BY public.github_repositories.id;


--
-- Name: ingest_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events (
    id bigint NOT NULL,
    api_key_id bigint NOT NULL,
    context jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    event_type integer NOT NULL,
    fingerprint character varying,
    level character varying,
    message text NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    project_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    error_group_id bigint
);


--
-- Name: ingest_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ingest_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ingest_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ingest_events_id_seq OWNED BY public.ingest_events.id;


--
-- Name: ingest_events_partitioned; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned (
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
PARTITION BY RANGE (occurred_at);


--
-- Name: ingest_events_partitioned_2026_02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_02 (
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
);


--
-- Name: ingest_events_partitioned_2026_03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_03 (
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
);


--
-- Name: ingest_events_partitioned_2026_04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_04 (
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
);


--
-- Name: ingest_events_partitioned_2026_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_05 (
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
);


--
-- Name: ingest_events_partitioned_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_06 (
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
);


--
-- Name: ingest_events_partitioned_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_07 (
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
);


--
-- Name: ingest_events_partitioned_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_08 (
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
);


--
-- Name: ingest_events_partitioned_2026_09; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_09 (
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
);


--
-- Name: ingest_events_partitioned_2026_10; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_10 (
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
);


--
-- Name: ingest_events_partitioned_2026_11; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_11 (
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
);


--
-- Name: ingest_events_partitioned_2026_12; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2026_12 (
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
);


--
-- Name: ingest_events_partitioned_2027_01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2027_01 (
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
);


--
-- Name: ingest_events_partitioned_2027_02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2027_02 (
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
);


--
-- Name: ingest_events_partitioned_2027_03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2027_03 (
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
);


--
-- Name: ingest_events_partitioned_2027_04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2027_04 (
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
);


--
-- Name: ingest_events_partitioned_2027_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2027_05 (
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
);


--
-- Name: ingest_events_partitioned_2027_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_2027_06 (
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
);


--
-- Name: ingest_events_partitioned_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingest_events_partitioned_default (
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
);


--
-- Name: mobile_ingest_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mobile_ingest_tokens (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id bigint NOT NULL,
    api_key_id bigint NOT NULL,
    token_digest character varying NOT NULL,
    platform character varying NOT NULL,
    service character varying NOT NULL,
    environment character varying NOT NULL,
    release character varying,
    session_id character varying,
    allowed_event_types jsonb DEFAULT '[]'::jsonb NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: mobile_ingest_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mobile_ingest_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mobile_ingest_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mobile_ingest_tokens_id_seq OWNED BY public.mobile_ingest_tokens.id;

--
-- Name: project_deployments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_deployments (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id bigint NOT NULL,
    project_source_repository_id bigint,
    github_repository_id bigint,
    provider character varying DEFAULT 'github'::character varying NOT NULL,
    repository_full_name character varying NOT NULL,
    environment character varying DEFAULT 'production'::character varying NOT NULL,
    release character varying NOT NULL,
    commit_sha character varying NOT NULL,
    branch character varying,
    deployed_at timestamp(6) without time zone,
    source character varying DEFAULT 'api'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: project_deployments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_deployments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_deployments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_deployments_id_seq OWNED BY public.project_deployments.id;


--
-- Name: project_github_installations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_github_installations (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id bigint NOT NULL,
    github_installation_id bigint NOT NULL,
    linked_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: project_github_installations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_github_installations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_github_installations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_github_installations_id_seq OWNED BY public.project_github_installations.id;


--
-- Name: project_integration_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_integration_settings (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    provider character varying NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    account_id character varying,
    external_project_id character varying,
    external_project_name character varying,
    credential_reference character varying,
    last_imported_at timestamp(6) without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: project_integration_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_integration_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_integration_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_integration_settings_id_seq OWNED BY public.project_integration_settings.id;


--
-- Name: project_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_memberships (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: project_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_memberships_id_seq OWNED BY public.project_memberships.id;


--
-- Name: project_notification_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_notification_preferences (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id bigint NOT NULL,
    user_id bigint NOT NULL,
    first_occurrence_enabled boolean DEFAULT true NOT NULL,
    digest_frequency character varying DEFAULT 'none'::character varying NOT NULL,
    digest_send_hour integer DEFAULT 9 NOT NULL,
    time_zone character varying DEFAULT 'UTC'::character varying NOT NULL,
    send_empty_digest boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    regression_enabled boolean DEFAULT true NOT NULL,
    frequent_error_enabled boolean DEFAULT false NOT NULL,
    frequent_error_threshold_count integer DEFAULT 25 NOT NULL,
    frequent_error_window_minutes integer DEFAULT 60 NOT NULL,
    milestone_alerts_enabled boolean DEFAULT false NOT NULL,
    workflow_mode character varying DEFAULT 'assigned_to_me'::character varying NOT NULL,
    monitor_alerts_enabled boolean DEFAULT true NOT NULL,
    project_spike_enabled boolean DEFAULT false NOT NULL,
    project_spike_threshold_count integer DEFAULT 100 NOT NULL,
    project_spike_window_minutes integer DEFAULT 15 NOT NULL,
    performance_alerts_enabled boolean DEFAULT false NOT NULL,
    performance_p95_threshold_ms integer DEFAULT 1000 NOT NULL,
    release_notifications_enabled boolean DEFAULT false NOT NULL,
    usage_notifications_enabled boolean DEFAULT true NOT NULL,
    retention_notifications_enabled boolean DEFAULT true NOT NULL,
    environment_filter character varying DEFAULT 'all'::character varying NOT NULL,
    severity_filter character varying DEFAULT 'all'::character varying NOT NULL,
    status_filter character varying DEFAULT 'unresolved'::character varying NOT NULL,
    immediate_email_limit_per_hour integer DEFAULT 10 NOT NULL,
    quiet_hours_enabled boolean DEFAULT false NOT NULL,
    quiet_hours_start integer DEFAULT 22 NOT NULL,
    quiet_hours_end integer DEFAULT 7 NOT NULL
);


--
-- Name: project_notification_preferences_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_notification_preferences_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_notification_preferences_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_notification_preferences_id_seq OWNED BY public.project_notification_preferences.id;


--
-- Name: project_retention_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_retention_policies (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    hot_retention_days integer DEFAULT 30 NOT NULL,
    trace_retention_days integer DEFAULT 30 NOT NULL,
    error_retention_days integer,
    archive_enabled boolean DEFAULT false NOT NULL,
    archive_before_delete boolean DEFAULT false NOT NULL,
    last_archive_run_at timestamp(6) without time zone,
    last_retention_run_at timestamp(6) without time zone,
    last_retention_result jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: project_retention_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_retention_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_retention_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_retention_policies_id_seq OWNED BY public.project_retention_policies.id;


--
-- Name: project_source_repositories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_source_repositories (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    github_installation_id bigint,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    provider character varying DEFAULT 'github'::character varying NOT NULL,
    external_id bigint,
    full_name character varying NOT NULL,
    owner_name character varying NOT NULL,
    repo_name character varying NOT NULL,
    default_branch character varying,
    runtime_root character varying,
    source_root character varying,
    enabled boolean DEFAULT true NOT NULL,
    last_synced_at timestamp(6) without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    github_repository_id bigint
);


--
-- Name: project_source_repositories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_source_repositories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_source_repositories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_source_repositories_id_seq OWNED BY public.project_source_repositories.id;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    description text,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_kind character varying DEFAULT 'ruby'::character varying NOT NULL,
    archived_at timestamp(6) without time zone,
    public_api_rate_limit_requests_override integer,
    public_api_rate_limit_period_seconds_override integer,
    public_api_auth_failure_rate_limit_requests_override integer
);


--
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.projects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: telemetry_archives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_archives (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    record_type character varying NOT NULL,
    scope character varying NOT NULL,
    status character varying DEFAULT 'completed'::character varying NOT NULL,
    before_at timestamp(6) without time zone NOT NULL,
    after_at timestamp(6) without time zone,
    rows integer DEFAULT 0 NOT NULL,
    bytes bigint DEFAULT 0 NOT NULL,
    objects jsonb DEFAULT '[]'::jsonb NOT NULL,
    dry_run boolean DEFAULT false NOT NULL,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: telemetry_archives_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.telemetry_archives_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: telemetry_archives_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.telemetry_archives_id_seq OWNED BY public.telemetry_archives.id;


--
-- Name: trace_spans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trace_spans (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    api_key_id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    trace_id character varying NOT NULL,
    span_id character varying NOT NULL,
    parent_span_id character varying,
    name character varying NOT NULL,
    kind character varying DEFAULT 'internal'::character varying NOT NULL,
    status character varying,
    duration_ms double precision DEFAULT 0.0 NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    ended_at timestamp(6) without time zone,
    context jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: trace_spans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trace_spans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trace_spans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trace_spans_id_seq OWNED BY public.trace_spans.id;


--
-- Name: user_notification_dismissals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_notification_dismissals (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id bigint NOT NULL,
    notification_key character varying NOT NULL,
    dismissed_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_notification_dismissals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_notification_dismissals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_notification_dismissals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_notification_dismissals_id_seq OWNED BY public.user_notification_dismissals.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    remember_created_at timestamp(6) without time zone,
    reset_password_sent_at timestamp(6) without time zone,
    reset_password_token character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    confirmation_token character varying,
    confirmed_at timestamp(6) without time zone,
    confirmation_sent_at timestamp(6) without time zone,
    unconfirmed_email character varying,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: ingest_events_partitioned_2026_02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_02 FOR VALUES FROM ('2026-02-01 00:00:00') TO ('2026-03-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_03 FOR VALUES FROM ('2026-03-01 00:00:00') TO ('2026-04-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_04 FOR VALUES FROM ('2026-04-01 00:00:00') TO ('2026-05-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_05 FOR VALUES FROM ('2026-05-01 00:00:00') TO ('2026-06-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00') TO ('2026-07-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00') TO ('2026-08-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00') TO ('2026-09-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_09; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_09 FOR VALUES FROM ('2026-09-01 00:00:00') TO ('2026-10-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_10; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_10 FOR VALUES FROM ('2026-10-01 00:00:00') TO ('2026-11-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_11; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_11 FOR VALUES FROM ('2026-11-01 00:00:00') TO ('2026-12-01 00:00:00');


--
-- Name: ingest_events_partitioned_2026_12; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2026_12 FOR VALUES FROM ('2026-12-01 00:00:00') TO ('2027-01-01 00:00:00');


--
-- Name: ingest_events_partitioned_2027_01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2027_01 FOR VALUES FROM ('2027-01-01 00:00:00') TO ('2027-02-01 00:00:00');


--
-- Name: ingest_events_partitioned_2027_02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2027_02 FOR VALUES FROM ('2027-02-01 00:00:00') TO ('2027-03-01 00:00:00');


--
-- Name: ingest_events_partitioned_2027_03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2027_03 FOR VALUES FROM ('2027-03-01 00:00:00') TO ('2027-04-01 00:00:00');


--
-- Name: ingest_events_partitioned_2027_04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2027_04 FOR VALUES FROM ('2027-04-01 00:00:00') TO ('2027-05-01 00:00:00');


--
-- Name: ingest_events_partitioned_2027_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2027_05 FOR VALUES FROM ('2027-05-01 00:00:00') TO ('2027-06-01 00:00:00');


--
-- Name: ingest_events_partitioned_2027_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_2027_06 FOR VALUES FROM ('2027-06-01 00:00:00') TO ('2027-07-01 00:00:00');


--
-- Name: ingest_events_partitioned_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned ATTACH PARTITION public.ingest_events_partitioned_default DEFAULT;


--
-- Name: api_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys ALTER COLUMN id SET DEFAULT nextval('public.api_keys_id_seq'::regclass);


--
-- Name: check_in_monitors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_in_monitors ALTER COLUMN id SET DEFAULT nextval('public.check_in_monitors_id_seq'::regclass);


--
-- Name: cli_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cli_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.cli_access_tokens_id_seq'::regclass);


--
-- Name: cli_device_authorizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cli_device_authorizations ALTER COLUMN id SET DEFAULT nextval('public.cli_device_authorizations_id_seq'::regclass);


--
-- Name: email_notification_deliveries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_notification_deliveries ALTER COLUMN id SET DEFAULT nextval('public.email_notification_deliveries_id_seq'::regclass);


--
-- Name: error_group_external_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_group_external_links ALTER COLUMN id SET DEFAULT nextval('public.error_group_external_links_id_seq'::regclass);


--
-- Name: error_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups ALTER COLUMN id SET DEFAULT nextval('public.error_groups_id_seq'::regclass);


--
-- Name: error_occurrences id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_occurrences ALTER COLUMN id SET DEFAULT nextval('public.error_occurrences_id_seq'::regclass);


--
-- Name: github_installations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_installations ALTER COLUMN id SET DEFAULT nextval('public.github_installations_id_seq'::regclass);


--
-- Name: github_repositories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_repositories ALTER COLUMN id SET DEFAULT nextval('public.github_repositories_id_seq'::regclass);


--
-- Name: ingest_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events ALTER COLUMN id SET DEFAULT nextval('public.ingest_events_id_seq'::regclass);


--
-- Name: mobile_ingest_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mobile_ingest_tokens ALTER COLUMN id SET DEFAULT nextval('public.mobile_ingest_tokens_id_seq'::regclass);

--
-- Name: project_deployments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_deployments ALTER COLUMN id SET DEFAULT nextval('public.project_deployments_id_seq'::regclass);


--
-- Name: project_github_installations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_installations ALTER COLUMN id SET DEFAULT nextval('public.project_github_installations_id_seq'::regclass);


--
-- Name: project_integration_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_integration_settings ALTER COLUMN id SET DEFAULT nextval('public.project_integration_settings_id_seq'::regclass);


--
-- Name: project_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_memberships ALTER COLUMN id SET DEFAULT nextval('public.project_memberships_id_seq'::regclass);


--
-- Name: project_notification_preferences id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_notification_preferences ALTER COLUMN id SET DEFAULT nextval('public.project_notification_preferences_id_seq'::regclass);


--
-- Name: project_retention_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_retention_policies ALTER COLUMN id SET DEFAULT nextval('public.project_retention_policies_id_seq'::regclass);


--
-- Name: project_source_repositories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_source_repositories ALTER COLUMN id SET DEFAULT nextval('public.project_source_repositories_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- Name: telemetry_archives id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_archives ALTER COLUMN id SET DEFAULT nextval('public.telemetry_archives_id_seq'::regclass);


--
-- Name: trace_spans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trace_spans ALTER COLUMN id SET DEFAULT nextval('public.trace_spans_id_seq'::regclass);


--
-- Name: user_notification_dismissals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_notification_dismissals ALTER COLUMN id SET DEFAULT nextval('public.user_notification_dismissals_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: check_in_monitors check_in_monitors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_in_monitors
    ADD CONSTRAINT check_in_monitors_pkey PRIMARY KEY (id);


--
-- Name: cli_access_tokens cli_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cli_access_tokens
    ADD CONSTRAINT cli_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: cli_device_authorizations cli_device_authorizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cli_device_authorizations
    ADD CONSTRAINT cli_device_authorizations_pkey PRIMARY KEY (id);


--
-- Name: email_notification_deliveries email_notification_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_notification_deliveries
    ADD CONSTRAINT email_notification_deliveries_pkey PRIMARY KEY (id);


--
-- Name: error_group_external_links error_group_external_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_group_external_links
    ADD CONSTRAINT error_group_external_links_pkey PRIMARY KEY (id);


--
-- Name: error_groups error_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT error_groups_pkey PRIMARY KEY (id);


--
-- Name: error_occurrences error_occurrences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_occurrences
    ADD CONSTRAINT error_occurrences_pkey PRIMARY KEY (id);


--
-- Name: github_installations github_installations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_installations
    ADD CONSTRAINT github_installations_pkey PRIMARY KEY (id);


--
-- Name: github_repositories github_repositories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_repositories
    ADD CONSTRAINT github_repositories_pkey PRIMARY KEY (id);


--
-- Name: ingest_events_partitioned ingest_events_partitioned_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned
    ADD CONSTRAINT ingest_events_partitioned_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_02 ingest_events_partitioned_2026_02_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_02
    ADD CONSTRAINT ingest_events_partitioned_2026_02_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_03 ingest_events_partitioned_2026_03_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_03
    ADD CONSTRAINT ingest_events_partitioned_2026_03_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_04 ingest_events_partitioned_2026_04_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_04
    ADD CONSTRAINT ingest_events_partitioned_2026_04_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_05 ingest_events_partitioned_2026_05_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_05
    ADD CONSTRAINT ingest_events_partitioned_2026_05_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_06 ingest_events_partitioned_2026_06_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_06
    ADD CONSTRAINT ingest_events_partitioned_2026_06_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_07 ingest_events_partitioned_2026_07_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_07
    ADD CONSTRAINT ingest_events_partitioned_2026_07_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_08 ingest_events_partitioned_2026_08_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_08
    ADD CONSTRAINT ingest_events_partitioned_2026_08_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_09 ingest_events_partitioned_2026_09_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_09
    ADD CONSTRAINT ingest_events_partitioned_2026_09_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_10 ingest_events_partitioned_2026_10_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_10
    ADD CONSTRAINT ingest_events_partitioned_2026_10_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_11 ingest_events_partitioned_2026_11_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_11
    ADD CONSTRAINT ingest_events_partitioned_2026_11_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_12 ingest_events_partitioned_2026_12_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2026_12
    ADD CONSTRAINT ingest_events_partitioned_2026_12_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_01 ingest_events_partitioned_2027_01_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2027_01
    ADD CONSTRAINT ingest_events_partitioned_2027_01_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_02 ingest_events_partitioned_2027_02_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2027_02
    ADD CONSTRAINT ingest_events_partitioned_2027_02_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_03 ingest_events_partitioned_2027_03_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2027_03
    ADD CONSTRAINT ingest_events_partitioned_2027_03_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_04 ingest_events_partitioned_2027_04_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2027_04
    ADD CONSTRAINT ingest_events_partitioned_2027_04_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_05 ingest_events_partitioned_2027_05_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2027_05
    ADD CONSTRAINT ingest_events_partitioned_2027_05_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_06 ingest_events_partitioned_2027_06_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_2027_06
    ADD CONSTRAINT ingest_events_partitioned_2027_06_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events_partitioned_default ingest_events_partitioned_default_id_occurred_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events_partitioned_default
    ADD CONSTRAINT ingest_events_partitioned_default_id_occurred_at_key UNIQUE (id, occurred_at);


--
-- Name: ingest_events ingest_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events
    ADD CONSTRAINT ingest_events_pkey PRIMARY KEY (id);


--
-- Name: mobile_ingest_tokens mobile_ingest_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mobile_ingest_tokens
    ADD CONSTRAINT mobile_ingest_tokens_pkey PRIMARY KEY (id);

--
-- Name: project_deployments project_deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_deployments
    ADD CONSTRAINT project_deployments_pkey PRIMARY KEY (id);


--
-- Name: project_github_installations project_github_installations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_installations
    ADD CONSTRAINT project_github_installations_pkey PRIMARY KEY (id);


--
-- Name: project_integration_settings project_integration_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_integration_settings
    ADD CONSTRAINT project_integration_settings_pkey PRIMARY KEY (id);


--
-- Name: project_memberships project_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_memberships
    ADD CONSTRAINT project_memberships_pkey PRIMARY KEY (id);


--
-- Name: project_notification_preferences project_notification_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_notification_preferences
    ADD CONSTRAINT project_notification_preferences_pkey PRIMARY KEY (id);


--
-- Name: project_retention_policies project_retention_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_retention_policies
    ADD CONSTRAINT project_retention_policies_pkey PRIMARY KEY (id);


--
-- Name: project_source_repositories project_source_repositories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_source_repositories
    ADD CONSTRAINT project_source_repositories_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: telemetry_archives telemetry_archives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_archives
    ADD CONSTRAINT telemetry_archives_pkey PRIMARY KEY (id);


--
-- Name: trace_spans trace_spans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trace_spans
    ADD CONSTRAINT trace_spans_pkey PRIMARY KEY (id);


--
-- Name: user_notification_dismissals user_notification_dismissals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_notification_dismissals
    ADD CONSTRAINT user_notification_dismissals_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_api_keys_project_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_project_created_at ON public.api_keys USING btree (project_id, created_at DESC);


--
-- Name: idx_api_keys_project_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_project_updated_at ON public.api_keys USING btree (project_id, updated_at DESC);


--
-- Name: idx_check_in_monitors_last_event_partition_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_in_monitors_last_event_partition_ref ON public.check_in_monitors USING btree (last_event_id, last_event_occurred_at) WHERE (last_event_id IS NOT NULL);


--
-- Name: idx_check_in_monitors_project_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_in_monitors_project_updated_at ON public.check_in_monitors USING btree (project_id, updated_at DESC);


--
-- Name: idx_check_in_monitors_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_check_in_monitors_uniqueness ON public.check_in_monitors USING btree (project_id, slug, environment);


--
-- Name: idx_email_deliveries_digest_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_deliveries_digest_lookup ON public.email_notification_deliveries USING btree (user_id, project_id, notification_kind, period_start_at);


--
-- Name: index_cli_access_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cli_access_tokens_on_token_digest ON public.cli_access_tokens USING btree (token_digest);


--
-- Name: index_cli_access_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cli_access_tokens_on_user_id ON public.cli_access_tokens USING btree (user_id);


--
-- Name: index_cli_access_tokens_on_user_id_and_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cli_access_tokens_on_user_id_and_expires_at ON public.cli_access_tokens USING btree (user_id, expires_at);


--
-- Name: index_cli_access_tokens_on_user_id_and_revoked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cli_access_tokens_on_user_id_and_revoked_at ON public.cli_access_tokens USING btree (user_id, revoked_at);


--
-- Name: index_cli_access_tokens_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cli_access_tokens_on_uuid ON public.cli_access_tokens USING btree (uuid);


--
-- Name: index_cli_device_authorizations_on_cli_access_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cli_device_authorizations_on_cli_access_token_id ON public.cli_device_authorizations USING btree (cli_access_token_id);


--
-- Name: index_cli_device_authorizations_on_device_code_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cli_device_authorizations_on_device_code_digest ON public.cli_device_authorizations USING btree (device_code_digest);


--
-- Name: index_cli_device_authorizations_on_status_and_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cli_device_authorizations_on_status_and_expires_at ON public.cli_device_authorizations USING btree (status, expires_at);


--
-- Name: index_cli_device_authorizations_on_user_code_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cli_device_authorizations_on_user_code_digest ON public.cli_device_authorizations USING btree (user_code_digest);


--
-- Name: index_cli_device_authorizations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cli_device_authorizations_on_user_id ON public.cli_device_authorizations USING btree (user_id);


--
-- Name: index_cli_device_authorizations_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cli_device_authorizations_on_uuid ON public.cli_device_authorizations USING btree (uuid);


--
-- Name: idx_email_deliveries_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_deliveries_status_created_at ON public.email_notification_deliveries USING btree (status, created_at);


--
-- Name: idx_error_groups_assignee_status_last_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_assignee_status_last_seen ON public.error_groups USING btree (assigned_user_id, status, last_seen_at DESC);


--
-- Name: idx_error_groups_latest_event_partition_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_latest_event_partition_ref ON public.error_groups USING btree (latest_event_id, latest_event_occurred_at) WHERE (latest_event_id IS NOT NULL);


--
-- Name: idx_error_groups_lower_fingerprint_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_lower_fingerprint_trgm ON public.error_groups USING gin (lower((fingerprint)::text) public.gin_trgm_ops);


--
-- Name: idx_error_groups_lower_stage_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_lower_stage_trgm ON public.error_groups USING gin (lower((stage)::text) public.gin_trgm_ops);


--
-- Name: idx_error_groups_lower_subtitle_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_lower_subtitle_trgm ON public.error_groups USING gin (lower((COALESCE(subtitle, ''::character varying))::text) public.gin_trgm_ops);


--
-- Name: idx_error_groups_lower_title_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_lower_title_trgm ON public.error_groups USING gin (lower((title)::text) public.gin_trgm_ops);


--
-- Name: idx_error_groups_project_assignee_seen_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_project_assignee_seen_cursor ON public.error_groups USING btree (project_id, assigned_user_id, status, last_seen_at DESC, id DESC);


--
-- Name: idx_error_groups_project_assignee_status_last_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_project_assignee_status_last_seen ON public.error_groups USING btree (project_id, assigned_user_id, status, last_seen_at DESC);


--
-- Name: idx_error_groups_project_retention; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_project_retention ON public.error_groups USING btree (project_id, status, last_seen_at, id);


--
-- Name: idx_error_groups_project_status_assignee_last_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_project_status_assignee_last_seen ON public.error_groups USING btree (project_id, status, assigned_user_id, last_seen_at DESC);


--
-- Name: idx_error_groups_project_status_first_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_project_status_first_seen ON public.error_groups USING btree (project_id, status, first_seen_at DESC);


--
-- Name: idx_error_groups_project_status_last_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_project_status_last_seen ON public.error_groups USING btree (project_id, status, last_seen_at DESC);


--
-- Name: idx_error_groups_project_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_project_updated_at ON public.error_groups USING btree (project_id, updated_at DESC);


--
-- Name: idx_error_occurrences_event_partition_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_occurrences_event_partition_ref ON public.error_occurrences USING btree (ingest_event_id, ingest_event_occurred_at);


--
-- Name: idx_ingest_events_part_release_health_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_release_health_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_02; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_02 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_03; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_03 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_04; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_04 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_05; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_05 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_06; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_06 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_07; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_07 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_08; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_08 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_09; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_09 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_10; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_10 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_11 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2026_12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2026_12 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2027_01; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2027_01 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2027_02; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2027_02 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2027_03; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2027_03 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2027_04; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2027_04 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2027_05; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2027_05 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_2027_06; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_2027_06 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_iep_release_health_default; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_iep_release_health_default ON public.ingest_events_partitioned_default USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_activity_env_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_activity_env_cursor ON public.ingest_events USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: idx_ingest_events_activity_release_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_activity_release_cursor ON public.ingest_events USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: idx_ingest_events_cf_pages_deployment_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_cf_pages_deployment_occurred ON public.ingest_events USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: idx_ingest_events_context_path_ops; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_context_path_ops ON public.ingest_events USING gin (context jsonb_path_ops);


--
-- Name: idx_ingest_events_part_activity_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_activity_cursor ON ONLY public.ingest_events_partitioned USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: idx_ingest_events_part_activity_env_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_activity_env_cursor ON ONLY public.ingest_events_partitioned USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: idx_ingest_events_part_activity_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_activity_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: idx_ingest_events_part_activity_release_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_activity_release_cursor ON ONLY public.ingest_events_partitioned USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: idx_ingest_events_part_cf_pages_deployment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_cf_pages_deployment ON ONLY public.ingest_events_partitioned USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: idx_ingest_events_part_context_path_ops; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_context_path_ops ON ONLY public.ingest_events_partitioned USING gin (context jsonb_path_ops);


--
-- Name: idx_ingest_events_part_db_query_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_db_query_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: idx_ingest_events_part_environment_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_environment_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: idx_ingest_events_part_metric_message; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_metric_message ON ONLY public.ingest_events_partitioned USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: idx_ingest_events_part_occurred_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_occurred_type ON ONLY public.ingest_events_partitioned USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: idx_ingest_events_part_platform_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_platform_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_part_release_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_release_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_part_retention_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_retention_created ON ONLY public.ingest_events_partitioned USING btree (created_at, id);


--
-- Name: idx_ingest_events_part_service_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_service_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_part_transactions; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_transactions ON ONLY public.ingest_events_partitioned USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: idx_ingest_events_part_type_retention; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_type_retention ON ONLY public.ingest_events_partitioned USING btree (project_id, event_type, occurred_at, id);


--
-- Name: idx_ingest_events_part_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_part_updated_at ON ONLY public.ingest_events_partitioned USING btree (project_id, updated_at DESC);


--
-- Name: idx_ingest_events_project_activity_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_activity_cursor ON public.ingest_events USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: idx_ingest_events_project_activity_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_activity_occurred ON public.ingest_events USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: idx_ingest_events_project_db_query_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_db_query_occurred ON public.ingest_events USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: idx_ingest_events_project_environment_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_environment_occurred ON public.ingest_events USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: idx_ingest_events_project_metric_message_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_metric_message_occurred ON public.ingest_events USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: idx_ingest_events_project_occurred_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_occurred_type ON public.ingest_events USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: idx_ingest_events_project_platform_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_platform_occurred ON public.ingest_events USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_project_release_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_release_occurred ON public.ingest_events USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_project_service_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_service_occurred ON public.ingest_events USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_project_transactions_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_transactions_occurred ON public.ingest_events USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: idx_ingest_events_project_type_retention; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_type_retention ON public.ingest_events USING btree (project_id, event_type, occurred_at, id);


--
-- Name: idx_ingest_events_project_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_project_updated_at ON public.ingest_events USING btree (project_id, updated_at DESC);


--
-- Name: idx_ingest_events_release_health_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_release_health_occurred ON public.ingest_events USING btree (project_id, occurred_at DESC, ((context ->> 'release'::text))) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: idx_ingest_events_retention_created_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ingest_events_retention_created_id ON public.ingest_events USING btree (created_at, id);


--
-- Name: idx_on_enabled_last_imported_at_ae810e9f88; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_enabled_last_imported_at_ae810e9f88 ON public.project_integration_settings USING btree (enabled, last_imported_at);


--
-- Name: idx_on_project_id_provider_full_name_6dea472798; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_project_id_provider_full_name_6dea472798 ON public.project_source_repositories USING btree (project_id, provider, full_name);


--
-- Name: idx_on_project_id_provider_link_type_d4cae99367; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_project_id_provider_link_type_d4cae99367 ON public.error_group_external_links USING btree (project_id, provider, link_type);


--
-- Name: idx_on_project_id_release_environment_84f39b9a75; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_project_id_release_environment_84f39b9a75 ON public.project_deployments USING btree (project_id, release, environment);


--
-- Name: idx_project_github_installations_project_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_project_github_installations_project_installation ON public.project_github_installations USING btree (project_id, github_installation_id);


--
-- Name: idx_project_integrations_provider_enabled_imported; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_integrations_provider_enabled_imported ON public.project_integration_settings USING btree (provider, enabled, last_imported_at);


--
-- Name: idx_project_memberships_user_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_memberships_user_project ON public.project_memberships USING btree (user_id, project_id);


--
-- Name: idx_project_notification_preferences_digest_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_notification_preferences_digest_due ON public.project_notification_preferences USING btree (digest_frequency, digest_send_hour);


--
-- Name: idx_project_notification_preferences_monitors; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_notification_preferences_monitors ON public.project_notification_preferences USING btree (project_id, monitor_alerts_enabled);


--
-- Name: idx_project_notification_preferences_regression; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_notification_preferences_regression ON public.project_notification_preferences USING btree (project_id, regression_enabled);


--
-- Name: idx_project_notification_preferences_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_project_notification_preferences_uniqueness ON public.project_notification_preferences USING btree (project_id, user_id);


--
-- Name: idx_projects_user_archived_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_projects_user_archived_at ON public.projects USING btree (user_id, archived_at);


--
-- Name: idx_projects_user_archived_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_projects_user_archived_created_at ON public.projects USING btree (user_id, archived_at, created_at DESC);


--
-- Name: idx_projects_user_archived_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_projects_user_archived_name ON public.projects USING btree (user_id, archived_at, name);


--
-- Name: idx_telemetry_archives_project_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_telemetry_archives_project_created_at ON public.telemetry_archives USING btree (project_id, created_at DESC);


--
-- Name: idx_telemetry_archives_project_scope_status_before; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_telemetry_archives_project_scope_status_before ON public.telemetry_archives USING btree (project_id, scope, status, before_at DESC);


--
-- Name: idx_trace_spans_project_retention; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trace_spans_project_retention ON public.trace_spans USING btree (project_id, started_at, id);


--
-- Name: idx_trace_spans_project_root_duration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trace_spans_project_root_duration ON public.trace_spans USING btree (project_id, duration_ms DESC, started_at DESC) WHERE (((kind)::text = ANY (ARRAY[('server'::character varying)::text, ('browser'::character varying)::text])) AND ((parent_span_id IS NULL) OR ((parent_span_id)::text = ''::text)));


--
-- Name: idx_trace_spans_retention_created_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trace_spans_retention_created_id ON public.trace_spans USING btree (created_at, id);


--
-- Name: idx_trace_spans_trace_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trace_spans_trace_parent ON public.trace_spans USING btree (project_id, trace_id, parent_span_id);


--
-- Name: idx_user_notification_dismissals_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_user_notification_dismissals_uniqueness ON public.user_notification_dismissals USING btree (user_id, notification_key);


--
-- Name: index_api_keys_on_last_used_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_keys_on_last_used_at ON public.api_keys USING btree (last_used_at);


--
-- Name: index_api_keys_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_keys_on_project_id ON public.api_keys USING btree (project_id);


--
-- Name: index_api_keys_on_revoked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_keys_on_revoked_at ON public.api_keys USING btree (revoked_at);


--
-- Name: index_api_keys_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_keys_on_token_digest ON public.api_keys USING btree (token_digest);


--
-- Name: index_api_keys_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_keys_on_user_id ON public.api_keys USING btree (user_id);


--
-- Name: index_api_keys_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_keys_on_uuid ON public.api_keys USING btree (uuid);


--
-- Name: index_check_in_monitors_on_last_error_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_in_monitors_on_last_error_at ON public.check_in_monitors USING btree (last_error_at);


--
-- Name: index_check_in_monitors_on_last_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_in_monitors_on_last_event_id ON public.check_in_monitors USING btree (last_event_id);


--
-- Name: index_check_in_monitors_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_in_monitors_on_project_id ON public.check_in_monitors USING btree (project_id);


--
-- Name: index_check_in_monitors_on_project_id_and_last_check_in_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_in_monitors_on_project_id_and_last_check_in_at ON public.check_in_monitors USING btree (project_id, last_check_in_at);


--
-- Name: index_email_notification_deliveries_on_dedup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_email_notification_deliveries_on_dedup_key ON public.email_notification_deliveries USING btree (dedup_key);


--
-- Name: index_email_notification_deliveries_on_error_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_notification_deliveries_on_error_group_id ON public.email_notification_deliveries USING btree (error_group_id);


--
-- Name: index_email_notification_deliveries_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_notification_deliveries_on_project_id ON public.email_notification_deliveries USING btree (project_id);


--
-- Name: index_email_notification_deliveries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_notification_deliveries_on_user_id ON public.email_notification_deliveries USING btree (user_id);


--
-- Name: index_email_notification_deliveries_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_email_notification_deliveries_on_uuid ON public.email_notification_deliveries USING btree (uuid);


--
-- Name: index_error_group_external_links_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_group_external_links_on_created_by_id ON public.error_group_external_links USING btree (created_by_id);


--
-- Name: index_error_group_external_links_on_error_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_group_external_links_on_error_group_id ON public.error_group_external_links USING btree (error_group_id);


--
-- Name: index_error_group_external_links_on_error_group_id_and_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_group_external_links_on_error_group_id_and_url ON public.error_group_external_links USING btree (error_group_id, url);


--
-- Name: index_error_group_external_links_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_group_external_links_on_project_id ON public.error_group_external_links USING btree (project_id);


--
-- Name: index_error_group_external_links_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_group_external_links_on_uuid ON public.error_group_external_links USING btree (uuid);


--
-- Name: index_error_groups_on_archived_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_archived_at ON public.error_groups USING btree (archived_at);


--
-- Name: index_error_groups_on_assigned_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_assigned_by_user_id ON public.error_groups USING btree (assigned_by_user_id);


--
-- Name: index_error_groups_on_assigned_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_assigned_user_id ON public.error_groups USING btree (assigned_user_id);


--
-- Name: index_error_groups_on_ignored_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_ignored_at ON public.error_groups USING btree (ignored_at);


--
-- Name: index_error_groups_on_last_reopened_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_last_reopened_at ON public.error_groups USING btree (last_reopened_at);


--
-- Name: index_error_groups_on_latest_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_latest_event_id ON public.error_groups USING btree (latest_event_id);


--
-- Name: index_error_groups_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_project_id ON public.error_groups USING btree (project_id);


--
-- Name: index_error_groups_on_project_id_and_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_groups_on_project_id_and_fingerprint ON public.error_groups USING btree (project_id, fingerprint);


--
-- Name: index_error_groups_on_project_id_and_first_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_project_id_and_first_seen_at ON public.error_groups USING btree (project_id, first_seen_at);


--
-- Name: index_error_groups_on_project_id_and_introduced_in_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_project_id_and_introduced_in_release ON public.error_groups USING btree (project_id, introduced_in_release);


--
-- Name: index_error_groups_on_project_id_and_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_project_id_and_last_seen_at ON public.error_groups USING btree (project_id, last_seen_at);


--
-- Name: index_error_groups_on_project_id_and_regressed_in_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_project_id_and_regressed_in_release ON public.error_groups USING btree (project_id, regressed_in_release);


--
-- Name: index_error_groups_on_project_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_project_id_and_status ON public.error_groups USING btree (project_id, status);


--
-- Name: index_error_groups_on_resolved_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_groups_on_resolved_at ON public.error_groups USING btree (resolved_at);


--
-- Name: index_error_groups_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_groups_on_uuid ON public.error_groups USING btree (uuid);


--
-- Name: index_error_occurrences_on_error_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_occurrences_on_error_group_id ON public.error_occurrences USING btree (error_group_id);


--
-- Name: index_error_occurrences_on_error_group_id_and_ingest_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_occurrences_on_error_group_id_and_ingest_event_id ON public.error_occurrences USING btree (error_group_id, ingest_event_id);


--
-- Name: index_error_occurrences_on_error_group_id_and_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_occurrences_on_error_group_id_and_occurred_at ON public.error_occurrences USING btree (error_group_id, occurred_at);


--
-- Name: index_error_occurrences_on_ingest_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_occurrences_on_ingest_event_id ON public.error_occurrences USING btree (ingest_event_id);


--
-- Name: index_error_occurrences_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_occurrences_on_uuid ON public.error_occurrences USING btree (uuid);


--
-- Name: index_github_installations_on_account_login; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_github_installations_on_account_login ON public.github_installations USING btree (account_login);


--
-- Name: index_github_installations_on_installation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_github_installations_on_installation_id ON public.github_installations USING btree (installation_id);


--
-- Name: index_github_installations_on_installed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_github_installations_on_installed_by_id ON public.github_installations USING btree (installed_by_id);


--
-- Name: index_github_installations_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_github_installations_on_uuid ON public.github_installations USING btree (uuid);


--
-- Name: index_github_repositories_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_github_repositories_on_external_id ON public.github_repositories USING btree (external_id);


--
-- Name: index_github_repositories_on_full_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_github_repositories_on_full_name ON public.github_repositories USING btree (full_name);


--
-- Name: index_github_repositories_on_github_installation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_github_repositories_on_github_installation_id ON public.github_repositories USING btree (github_installation_id);


--
-- Name: index_github_repositories_on_github_installation_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_github_repositories_on_github_installation_id_and_active ON public.github_repositories USING btree (github_installation_id, active);


--
-- Name: index_ingest_events_on_api_key_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_on_api_key_id ON public.ingest_events USING btree (api_key_id);


--
-- Name: index_ingest_events_on_error_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_on_error_group_id ON public.ingest_events USING btree (error_group_id);


--
-- Name: index_ingest_events_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_on_project_id ON public.ingest_events USING btree (project_id);


--
-- Name: index_ingest_events_on_project_id_and_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_on_project_id_and_event_type ON public.ingest_events USING btree (project_id, event_type);


--
-- Name: index_ingest_events_on_project_id_and_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_on_project_id_and_occurred_at ON public.ingest_events USING btree (project_id, occurred_at);


--
-- Name: index_ingest_events_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ingest_events_on_uuid ON public.ingest_events USING btree (uuid);


--
-- Name: index_ingest_events_part_api_key_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_part_api_key_id ON ONLY public.ingest_events_partitioned USING btree (api_key_id);


--
-- Name: index_ingest_events_part_error_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_part_error_group_id ON ONLY public.ingest_events_partitioned USING btree (error_group_id);


--
-- Name: index_ingest_events_part_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_part_project_id ON ONLY public.ingest_events_partitioned USING btree (project_id);


--
-- Name: index_ingest_events_part_project_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_part_project_occurred ON ONLY public.ingest_events_partitioned USING btree (project_id, occurred_at);


--
-- Name: index_ingest_events_part_project_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_part_project_type ON ONLY public.ingest_events_partitioned USING btree (project_id, event_type);


--
-- Name: index_ingest_events_part_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingest_events_part_uuid ON ONLY public.ingest_events_partitioned USING btree (uuid);


--
-- Name: index_mobile_ingest_tokens_on_api_key_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mobile_ingest_tokens_on_api_key_id ON public.mobile_ingest_tokens USING btree (api_key_id);


--
-- Name: index_mobile_ingest_tokens_on_api_key_id_and_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mobile_ingest_tokens_on_api_key_id_and_expires_at ON public.mobile_ingest_tokens USING btree (api_key_id, expires_at);


--
-- Name: index_mobile_ingest_tokens_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mobile_ingest_tokens_on_project_id ON public.mobile_ingest_tokens USING btree (project_id);


--
-- Name: index_mobile_ingest_tokens_on_project_id_and_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mobile_ingest_tokens_on_project_id_and_expires_at ON public.mobile_ingest_tokens USING btree (project_id, expires_at);


--
-- Name: index_mobile_ingest_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mobile_ingest_tokens_on_token_digest ON public.mobile_ingest_tokens USING btree (token_digest);


--
-- Name: index_mobile_ingest_tokens_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mobile_ingest_tokens_on_uuid ON public.mobile_ingest_tokens USING btree (uuid);

--
-- Name: index_project_deployments_on_github_repository_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_deployments_on_github_repository_id ON public.project_deployments USING btree (github_repository_id);


--
-- Name: index_project_deployments_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_deployments_on_project_id ON public.project_deployments USING btree (project_id);


--
-- Name: index_project_deployments_on_project_id_and_commit_sha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_deployments_on_project_id_and_commit_sha ON public.project_deployments USING btree (project_id, commit_sha);


--
-- Name: index_project_deployments_on_project_repo_env_release; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_deployments_on_project_repo_env_release ON public.project_deployments USING btree (project_id, repository_full_name, environment, release);


--
-- Name: index_project_deployments_on_project_source_repository_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_deployments_on_project_source_repository_id ON public.project_deployments USING btree (project_source_repository_id);


--
-- Name: index_project_deployments_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_deployments_on_uuid ON public.project_deployments USING btree (uuid);


--
-- Name: index_project_github_installations_on_github_installation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_github_installations_on_github_installation_id ON public.project_github_installations USING btree (github_installation_id);


--
-- Name: index_project_github_installations_on_linked_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_github_installations_on_linked_by_id ON public.project_github_installations USING btree (linked_by_id);


--
-- Name: index_project_github_installations_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_github_installations_on_project_id ON public.project_github_installations USING btree (project_id);


--
-- Name: index_project_github_installations_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_github_installations_on_uuid ON public.project_github_installations USING btree (uuid);


--
-- Name: index_project_integration_settings_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_integration_settings_on_project_id ON public.project_integration_settings USING btree (project_id);


--
-- Name: index_project_integration_settings_on_project_id_and_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_integration_settings_on_project_id_and_provider ON public.project_integration_settings USING btree (project_id, provider);


--
-- Name: index_project_integration_settings_on_provider_and_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_integration_settings_on_provider_and_enabled ON public.project_integration_settings USING btree (provider, enabled);


--
-- Name: index_project_integration_settings_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_integration_settings_on_uuid ON public.project_integration_settings USING btree (uuid);


--
-- Name: index_project_memberships_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_memberships_on_project_id ON public.project_memberships USING btree (project_id);


--
-- Name: index_project_memberships_on_project_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_memberships_on_project_id_and_user_id ON public.project_memberships USING btree (project_id, user_id);


--
-- Name: index_project_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_memberships_on_user_id ON public.project_memberships USING btree (user_id);


--
-- Name: index_project_memberships_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_memberships_on_uuid ON public.project_memberships USING btree (uuid);


--
-- Name: index_project_notification_preferences_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_notification_preferences_on_project_id ON public.project_notification_preferences USING btree (project_id);


--
-- Name: index_project_notification_preferences_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_notification_preferences_on_user_id ON public.project_notification_preferences USING btree (user_id);


--
-- Name: index_project_notification_preferences_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_notification_preferences_on_uuid ON public.project_notification_preferences USING btree (uuid);


--
-- Name: index_project_retention_policies_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_retention_policies_on_project_id ON public.project_retention_policies USING btree (project_id);


--
-- Name: index_project_source_repositories_on_github_installation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_source_repositories_on_github_installation_id ON public.project_source_repositories USING btree (github_installation_id);


--
-- Name: index_project_source_repositories_on_github_repository_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_source_repositories_on_github_repository_id ON public.project_source_repositories USING btree (github_repository_id);


--
-- Name: index_project_source_repositories_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_source_repositories_on_project_id ON public.project_source_repositories USING btree (project_id);


--
-- Name: index_project_source_repositories_on_project_id_and_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_source_repositories_on_project_id_and_enabled ON public.project_source_repositories USING btree (project_id, enabled);


--
-- Name: index_project_source_repositories_on_provider_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_source_repositories_on_provider_and_external_id ON public.project_source_repositories USING btree (provider, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_project_source_repositories_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_source_repositories_on_uuid ON public.project_source_repositories USING btree (uuid);


--
-- Name: index_projects_on_integration_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_integration_kind ON public.projects USING btree (integration_kind);


--
-- Name: index_projects_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_user_id ON public.projects USING btree (user_id);


--
-- Name: index_projects_on_user_id_and_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_user_id_and_slug ON public.projects USING btree (user_id, slug);


--
-- Name: index_projects_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_uuid ON public.projects USING btree (uuid);


--
-- Name: index_telemetry_archives_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telemetry_archives_on_project_id ON public.telemetry_archives USING btree (project_id);


--
-- Name: index_trace_spans_on_api_key_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trace_spans_on_api_key_id ON public.trace_spans USING btree (api_key_id);


--
-- Name: index_trace_spans_on_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trace_spans_on_context ON public.trace_spans USING gin (context jsonb_path_ops);


--
-- Name: index_trace_spans_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trace_spans_on_project_id ON public.trace_spans USING btree (project_id);


--
-- Name: index_trace_spans_on_project_id_and_kind_and_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trace_spans_on_project_id_and_kind_and_started_at ON public.trace_spans USING btree (project_id, kind, started_at DESC);


--
-- Name: index_trace_spans_on_project_id_and_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trace_spans_on_project_id_and_started_at ON public.trace_spans USING btree (project_id, started_at DESC);


--
-- Name: index_trace_spans_on_project_id_and_trace_id_and_span_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trace_spans_on_project_id_and_trace_id_and_span_id ON public.trace_spans USING btree (project_id, trace_id, span_id);


--
-- Name: index_trace_spans_on_project_id_and_trace_id_and_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trace_spans_on_project_id_and_trace_id_and_started_at ON public.trace_spans USING btree (project_id, trace_id, started_at DESC);


--
-- Name: index_trace_spans_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trace_spans_on_uuid ON public.trace_spans USING btree (uuid);


--
-- Name: index_user_notification_dismissals_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_notification_dismissals_on_user_id ON public.user_notification_dismissals USING btree (user_id);


--
-- Name: index_user_notification_dismissals_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_notification_dismissals_on_uuid ON public.user_notification_dismissals USING btree (uuid);


--
-- Name: index_users_on_confirmation_sent_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_confirmation_sent_at ON public.users USING btree (confirmation_sent_at);


--
-- Name: index_users_on_confirmation_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_confirmation_token ON public.users USING btree (confirmation_token);


--
-- Name: index_users_on_confirmed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_confirmed_at ON public.users USING btree (confirmed_at);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_remember_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_remember_created_at ON public.users USING btree (remember_created_at);


--
-- Name: index_users_on_reset_password_sent_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_reset_password_sent_at ON public.users USING btree (reset_password_sent_at);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_uuid ON public.users USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_02_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_api_key_id_idx ON public.ingest_events_partitioned_2026_02 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_02_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_context_idx ON public.ingest_events_partitioned_2026_02 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_02_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_created_at_id_idx ON public.ingest_events_partitioned_2026_02 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_02_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_error_group_id_idx ON public.ingest_events_partitioned_2026_02 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_02_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_event_type_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_02_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_02_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_02_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_02_uuid_idx ON public.ingest_events_partitioned_2026_02 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_03_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_api_key_id_idx ON public.ingest_events_partitioned_2026_03 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_03_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_context_idx ON public.ingest_events_partitioned_2026_03 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_03_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_created_at_id_idx ON public.ingest_events_partitioned_2026_03 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_03_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_error_group_id_idx ON public.ingest_events_partitioned_2026_03 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_03_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_event_type_idx ON public.ingest_events_partitioned_2026_03 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_03_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_idx ON public.ingest_events_partitioned_2026_03 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_03 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_03 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_03_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_03 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_03_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_03_uuid_idx ON public.ingest_events_partitioned_2026_03 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_04_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_api_key_id_idx ON public.ingest_events_partitioned_2026_04 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_04_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_context_idx ON public.ingest_events_partitioned_2026_04 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_04_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_created_at_id_idx ON public.ingest_events_partitioned_2026_04 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_04_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_error_group_id_idx ON public.ingest_events_partitioned_2026_04 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_04_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_event_type_idx ON public.ingest_events_partitioned_2026_04 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_04_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_idx ON public.ingest_events_partitioned_2026_04 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_04 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_04 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_04_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_04 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_04_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_04_uuid_idx ON public.ingest_events_partitioned_2026_04 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_05_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_api_key_id_idx ON public.ingest_events_partitioned_2026_05 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_05_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_context_idx ON public.ingest_events_partitioned_2026_05 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_05_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_created_at_id_idx ON public.ingest_events_partitioned_2026_05 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_05_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_error_group_id_idx ON public.ingest_events_partitioned_2026_05 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_05_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_event_type_idx ON public.ingest_events_partitioned_2026_05 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_05_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_idx ON public.ingest_events_partitioned_2026_05 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_05 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_05 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_05_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_05 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_05_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_05_uuid_idx ON public.ingest_events_partitioned_2026_05 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_06_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_api_key_id_idx ON public.ingest_events_partitioned_2026_06 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_06_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_context_idx ON public.ingest_events_partitioned_2026_06 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_06_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_created_at_id_idx ON public.ingest_events_partitioned_2026_06 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_06_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_error_group_id_idx ON public.ingest_events_partitioned_2026_06 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_06_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_event_type_idx ON public.ingest_events_partitioned_2026_06 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_06_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_idx ON public.ingest_events_partitioned_2026_06 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_06 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_06 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_06_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_06 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_06_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_06_uuid_idx ON public.ingest_events_partitioned_2026_06 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_07_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_api_key_id_idx ON public.ingest_events_partitioned_2026_07 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_07_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_context_idx ON public.ingest_events_partitioned_2026_07 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_07_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_created_at_id_idx ON public.ingest_events_partitioned_2026_07 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_07_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_error_group_id_idx ON public.ingest_events_partitioned_2026_07 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_07_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_event_type_idx ON public.ingest_events_partitioned_2026_07 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_07_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_idx ON public.ingest_events_partitioned_2026_07 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_07 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_07 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_07_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_07 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_07_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_07_uuid_idx ON public.ingest_events_partitioned_2026_07 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_08_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_api_key_id_idx ON public.ingest_events_partitioned_2026_08 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_08_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_context_idx ON public.ingest_events_partitioned_2026_08 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_08_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_created_at_id_idx ON public.ingest_events_partitioned_2026_08 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_08_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_error_group_id_idx ON public.ingest_events_partitioned_2026_08 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_08_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_event_type_idx ON public.ingest_events_partitioned_2026_08 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_08_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_idx ON public.ingest_events_partitioned_2026_08 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_08 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_08 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_08_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_08 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_08_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_08_uuid_idx ON public.ingest_events_partitioned_2026_08 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_09_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_api_key_id_idx ON public.ingest_events_partitioned_2026_09 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_09_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_context_idx ON public.ingest_events_partitioned_2026_09 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_09_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_created_at_id_idx ON public.ingest_events_partitioned_2026_09 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_09_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_error_group_id_idx ON public.ingest_events_partitioned_2026_09 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_09_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_event_type_idx ON public.ingest_events_partitioned_2026_09 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_09_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_idx ON public.ingest_events_partitioned_2026_09 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_09 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_09 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_09_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_09 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_09_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_09_uuid_idx ON public.ingest_events_partitioned_2026_09 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_10_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_api_key_id_idx ON public.ingest_events_partitioned_2026_10 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_10_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_context_idx ON public.ingest_events_partitioned_2026_10 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_10_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_created_at_id_idx ON public.ingest_events_partitioned_2026_10 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_10_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_error_group_id_idx ON public.ingest_events_partitioned_2026_10 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_10_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_event_type_idx ON public.ingest_events_partitioned_2026_10 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_10_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_idx ON public.ingest_events_partitioned_2026_10 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_10 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_10 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_10_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_10 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_10_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_10_uuid_idx ON public.ingest_events_partitioned_2026_10 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_11_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_api_key_id_idx ON public.ingest_events_partitioned_2026_11 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_11_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_context_idx ON public.ingest_events_partitioned_2026_11 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_11_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_created_at_id_idx ON public.ingest_events_partitioned_2026_11 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_11_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_error_group_id_idx ON public.ingest_events_partitioned_2026_11 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_11_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_event_type_idx ON public.ingest_events_partitioned_2026_11 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_11_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_idx ON public.ingest_events_partitioned_2026_11 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_11 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_11 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_11_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_11 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_11_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_11_uuid_idx ON public.ingest_events_partitioned_2026_11 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026_12_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_api_key_id_idx ON public.ingest_events_partitioned_2026_12 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2026_12_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_context_idx ON public.ingest_events_partitioned_2026_12 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2026_12_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_created_at_id_idx ON public.ingest_events_partitioned_2026_12 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2026_12_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_error_group_id_idx ON public.ingest_events_partitioned_2026_12 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2026_12_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_event_type_idx ON public.ingest_events_partitioned_2026_12 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2026_12_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_idx ON public.ingest_events_partitioned_2026_12 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2026_12 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_occurred_at_idx ON public.ingest_events_partitioned_2026_12 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2026_12_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_project_id_updated_at_idx ON public.ingest_events_partitioned_2026_12 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2026_12_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_12_uuid_idx ON public.ingest_events_partitioned_2026_12 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2026__project_id_expr_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026__project_id_expr_occurred_at_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx1 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx2 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx3 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx4 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx5 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx6 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx7 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx8 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2026_project_id_expr_occurred_at_idx9 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2027_01_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_api_key_id_idx ON public.ingest_events_partitioned_2027_01 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2027_01_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_context_idx ON public.ingest_events_partitioned_2027_01 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2027_01_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_created_at_id_idx ON public.ingest_events_partitioned_2027_01 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2027_01_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_error_group_id_idx ON public.ingest_events_partitioned_2027_01 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2027_01_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_event_type_idx ON public.ingest_events_partitioned_2027_01 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2027_01_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_idx ON public.ingest_events_partitioned_2027_01 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2027_01 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_occurred_at_idx ON public.ingest_events_partitioned_2027_01 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_01_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_project_id_updated_at_idx ON public.ingest_events_partitioned_2027_01 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2027_01_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_01_uuid_idx ON public.ingest_events_partitioned_2027_01 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2027_02_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_api_key_id_idx ON public.ingest_events_partitioned_2027_02 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2027_02_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_context_idx ON public.ingest_events_partitioned_2027_02 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2027_02_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_created_at_id_idx ON public.ingest_events_partitioned_2027_02 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2027_02_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_error_group_id_idx ON public.ingest_events_partitioned_2027_02 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2027_02_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_event_type_idx ON public.ingest_events_partitioned_2027_02 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2027_02_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_idx ON public.ingest_events_partitioned_2027_02 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2027_02 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_occurred_at_idx ON public.ingest_events_partitioned_2027_02 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_02_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_project_id_updated_at_idx ON public.ingest_events_partitioned_2027_02 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2027_02_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_02_uuid_idx ON public.ingest_events_partitioned_2027_02 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2027_03_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_api_key_id_idx ON public.ingest_events_partitioned_2027_03 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2027_03_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_context_idx ON public.ingest_events_partitioned_2027_03 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2027_03_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_created_at_id_idx ON public.ingest_events_partitioned_2027_03 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2027_03_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_error_group_id_idx ON public.ingest_events_partitioned_2027_03 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2027_03_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_event_type_idx ON public.ingest_events_partitioned_2027_03 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2027_03_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_idx ON public.ingest_events_partitioned_2027_03 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2027_03 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_occurred_at_idx ON public.ingest_events_partitioned_2027_03 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_03_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_project_id_updated_at_idx ON public.ingest_events_partitioned_2027_03 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2027_03_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_03_uuid_idx ON public.ingest_events_partitioned_2027_03 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2027_04_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_api_key_id_idx ON public.ingest_events_partitioned_2027_04 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2027_04_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_context_idx ON public.ingest_events_partitioned_2027_04 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2027_04_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_created_at_id_idx ON public.ingest_events_partitioned_2027_04 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2027_04_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_error_group_id_idx ON public.ingest_events_partitioned_2027_04 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2027_04_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_event_type_idx ON public.ingest_events_partitioned_2027_04 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2027_04_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_idx ON public.ingest_events_partitioned_2027_04 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2027_04 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_occurred_at_idx ON public.ingest_events_partitioned_2027_04 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_04_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_project_id_updated_at_idx ON public.ingest_events_partitioned_2027_04 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2027_04_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_04_uuid_idx ON public.ingest_events_partitioned_2027_04 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2027_05_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_api_key_id_idx ON public.ingest_events_partitioned_2027_05 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2027_05_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_context_idx ON public.ingest_events_partitioned_2027_05 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2027_05_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_created_at_id_idx ON public.ingest_events_partitioned_2027_05 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2027_05_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_error_group_id_idx ON public.ingest_events_partitioned_2027_05 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2027_05_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_event_type_idx ON public.ingest_events_partitioned_2027_05 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2027_05_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_idx ON public.ingest_events_partitioned_2027_05 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2027_05 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_occurred_at_idx ON public.ingest_events_partitioned_2027_05 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_05_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_project_id_updated_at_idx ON public.ingest_events_partitioned_2027_05 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2027_05_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_05_uuid_idx ON public.ingest_events_partitioned_2027_05 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2027_06_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_api_key_id_idx ON public.ingest_events_partitioned_2027_06 USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_2027_06_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_context_idx ON public.ingest_events_partitioned_2027_06 USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_2027_06_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_created_at_id_idx ON public.ingest_events_partitioned_2027_06 USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_2027_06_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_error_group_id_idx ON public.ingest_events_partitioned_2027_06 USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_2027_06_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_event_type_idx ON public.ingest_events_partitioned_2027_06 USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_2027_06_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_idx ON public.ingest_events_partitioned_2027_06 USING btree (project_id);


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_2027_06 USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_occurred_at_idx ON public.ingest_events_partitioned_2027_06 USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_2027_06_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_project_id_updated_at_idx ON public.ingest_events_partitioned_2027_06 USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_2027_06_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_06_uuid_idx ON public.ingest_events_partitioned_2027_06 USING btree (uuid);


--
-- Name: ingest_events_partitioned_2027__project_id_expr_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027__project_id_expr_occurred_at_idx ON public.ingest_events_partitioned_2027_01 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx1 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx2 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx3 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx4 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx5 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx6 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx7 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx8 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_2027_project_id_expr_occurred_at_idx9 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred__idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred__idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx1 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx2 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx3 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx4 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx5 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx6 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx7 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx8 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_coalesce_occurred_idx9 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx1 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx2 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx3 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx4 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx5 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx6 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx7 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx8 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurr_idx9 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurre_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_event_type_occurre_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx1 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx2 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx3 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx4 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx5 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx6 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx7 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx8 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at__idx9 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_i_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_i_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx10; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx10 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx11 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx12 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx13 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx14 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx15 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx16; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx16 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx17; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx17 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx18; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx18 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx19; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx19 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx20; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx20 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx21; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx21 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx22; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx22 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx23; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx23 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx24; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx24 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx25; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx25 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx26; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx26 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx27; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx27 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx28; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx28 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx29; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx29 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx30; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx30 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx31; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx31 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx32; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx32 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx33; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx33 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx34; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx34 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx35; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx35 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx36; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx36 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx37; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx37 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx38; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx38 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx39; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx39 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx40; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_expr_occurred_at_idx40 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx1 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx2 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx3 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx4 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx5 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx6 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx7 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx8 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred__idx9 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred_a_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_message_occurred_a_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx1 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx2 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx3 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx4 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx5 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx6 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx7 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx8 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_a_idx9 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_202_project_id_nullif_occurred_at_idx ON public.ingest_events_partitioned_2026_02 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx10; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx10 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx11 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx12 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx13 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx14 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx15 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx16; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx16 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx17; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx17 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx18; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx18 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx19; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx19 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx20; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx20 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx21; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx21 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx22; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx22 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx23; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx23 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx24; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx24 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx25; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx25 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx26; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx26 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx27; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx27 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx28; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx28 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx29; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx29 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx30; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx30 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx31; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx31 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx32; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx32 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx33; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_coalesce_occurred_idx33 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx10; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx10 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx11 ON public.ingest_events_partitioned_2026_02 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx12 ON public.ingest_events_partitioned_2026_03 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx13 ON public.ingest_events_partitioned_2026_04 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx14 ON public.ingest_events_partitioned_2026_05 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx15 ON public.ingest_events_partitioned_2026_06 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx16; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx16 ON public.ingest_events_partitioned_2026_07 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx17; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx17 ON public.ingest_events_partitioned_2026_08 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx18; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx18 ON public.ingest_events_partitioned_2026_09 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx19; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx19 ON public.ingest_events_partitioned_2026_10 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx20; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx20 ON public.ingest_events_partitioned_2026_11 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx21; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx21 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx22; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx22 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx23; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx23 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx24; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx24 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx25; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx25 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx26; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx26 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx27; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx27 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx28; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx28 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx29; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx29 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx30; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx30 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx31; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx31 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx32; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx32 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx33; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_event_type_occurr_idx33 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx10; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_expr_occurred_at__idx10 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_expr_occurred_at__idx11 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_expr_occurred_at__idx12 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_expr_occurred_at__idx13 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_expr_occurred_at__idx14 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_expr_occurred_at__idx15 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx16; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_expr_occurred_at__idx16 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx10; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_message_occurred__idx10 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_message_occurred__idx11 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_message_occurred__idx12 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_message_occurred__idx13 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_message_occurred__idx14 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_message_occurred__idx15 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx16; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_message_occurred__idx16 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx10; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_nullif_occurred_a_idx10 ON public.ingest_events_partitioned_2026_12 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_nullif_occurred_a_idx11 ON public.ingest_events_partitioned_2027_01 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx12; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_nullif_occurred_a_idx12 ON public.ingest_events_partitioned_2027_02 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_nullif_occurred_a_idx13 ON public.ingest_events_partitioned_2027_03 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_nullif_occurred_a_idx14 ON public.ingest_events_partitioned_2027_04 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_nullif_occurred_a_idx15 ON public.ingest_events_partitioned_2027_05 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx16; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_20_project_id_nullif_occurred_a_idx16 ON public.ingest_events_partitioned_2027_06 USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_def_project_id_coalesce_occurred__idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_def_project_id_coalesce_occurred__idx ON public.ingest_events_partitioned_default USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'production'::text), occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_def_project_id_coalesce_occurred_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_def_project_id_coalesce_occurred_idx1 ON public.ingest_events_partitioned_default USING btree (project_id, COALESCE(NULLIF((context ->> 'environment'::text), ''::text), 'unknown'::text), occurred_at DESC);


--
-- Name: ingest_events_partitioned_def_project_id_event_type_occurr_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_def_project_id_event_type_occurr_idx1 ON public.ingest_events_partitioned_default USING btree (project_id, event_type, occurred_at, id);


--
-- Name: ingest_events_partitioned_def_project_id_event_type_occurre_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_def_project_id_event_type_occurre_idx ON public.ingest_events_partitioned_default USING btree (project_id, event_type, occurred_at DESC);


--
-- Name: ingest_events_partitioned_def_project_id_expr_occurred_at_i_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_def_project_id_expr_occurred_at_i_idx ON public.ingest_events_partitioned_default USING btree (project_id, ((context ->> 'release'::text)), occurred_at DESC, id DESC) WHERE ((event_type <> 0) AND (COALESCE((context ->> 'release'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_def_project_id_message_occurred_a_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_def_project_id_message_occurred_a_idx ON public.ingest_events_partitioned_default USING btree (project_id, message, occurred_at DESC) WHERE (event_type = 1);


--
-- Name: ingest_events_partitioned_def_project_id_nullif_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_def_project_id_nullif_occurred_at_idx ON public.ingest_events_partitioned_default USING btree (project_id, NULLIF((context ->> 'release'::text), ''::text), occurred_at DESC) WHERE (COALESCE((context ->> 'release'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_defa_project_id_expr_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_defa_project_id_expr_occurred_at_idx1 ON public.ingest_events_partitioned_default USING btree (project_id, ((context ->> 'platform'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'platform'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_defa_project_id_expr_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_defa_project_id_expr_occurred_at_idx2 ON public.ingest_events_partitioned_default USING btree (project_id, ((context ->> 'service'::text)), occurred_at DESC) WHERE (COALESCE((context ->> 'service'::text), ''::text) <> ''::text);


--
-- Name: ingest_events_partitioned_defau_project_id_expr_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_defau_project_id_expr_occurred_at_idx ON public.ingest_events_partitioned_default USING btree (project_id, ((context ->> 'deployment_id'::text)), occurred_at DESC) WHERE (((context ->> 'platform'::text) = 'cloudflare_pages'::text) AND (COALESCE((context ->> 'deployment_id'::text), ''::text) <> ''::text));


--
-- Name: ingest_events_partitioned_default_api_key_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_api_key_id_idx ON public.ingest_events_partitioned_default USING btree (api_key_id);


--
-- Name: ingest_events_partitioned_default_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_context_idx ON public.ingest_events_partitioned_default USING gin (context jsonb_path_ops);


--
-- Name: ingest_events_partitioned_default_created_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_created_at_id_idx ON public.ingest_events_partitioned_default USING btree (created_at, id);


--
-- Name: ingest_events_partitioned_default_error_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_error_group_id_idx ON public.ingest_events_partitioned_default USING btree (error_group_id);


--
-- Name: ingest_events_partitioned_default_project_id_event_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_event_type_idx ON public.ingest_events_partitioned_default USING btree (project_id, event_type);


--
-- Name: ingest_events_partitioned_default_project_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_idx ON public.ingest_events_partitioned_default USING btree (project_id);


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_occurred_at_id_idx ON public.ingest_events_partitioned_default USING btree (project_id, occurred_at DESC, id DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_occurred_at_idx ON public.ingest_events_partitioned_default USING btree (project_id, occurred_at DESC) WHERE (event_type <> 0);


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_occurred_at_idx1 ON public.ingest_events_partitioned_default USING btree (project_id, occurred_at DESC) WHERE ((event_type = 1) AND (message = 'db.query'::text));


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_occurred_at_idx2 ON public.ingest_events_partitioned_default USING btree (project_id, occurred_at DESC) WHERE (event_type = 2);


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_occurred_at_idx3 ON public.ingest_events_partitioned_default USING btree (project_id, occurred_at);


--
-- Name: ingest_events_partitioned_default_project_id_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_project_id_updated_at_idx ON public.ingest_events_partitioned_default USING btree (project_id, updated_at DESC);


--
-- Name: ingest_events_partitioned_default_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingest_events_partitioned_default_uuid_idx ON public.ingest_events_partitioned_default USING btree (uuid);


--
-- Name: idx_iep_release_health_2026_02; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_02;


--
-- Name: idx_iep_release_health_2026_03; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_03;


--
-- Name: idx_iep_release_health_2026_04; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_04;


--
-- Name: idx_iep_release_health_2026_05; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_05;


--
-- Name: idx_iep_release_health_2026_06; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_06;


--
-- Name: idx_iep_release_health_2026_07; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_07;


--
-- Name: idx_iep_release_health_2026_08; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_08;


--
-- Name: idx_iep_release_health_2026_09; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_09;


--
-- Name: idx_iep_release_health_2026_10; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_10;


--
-- Name: idx_iep_release_health_2026_11; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_11;


--
-- Name: idx_iep_release_health_2026_12; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2026_12;


--
-- Name: idx_iep_release_health_2027_01; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2027_01;


--
-- Name: idx_iep_release_health_2027_02; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2027_02;


--
-- Name: idx_iep_release_health_2027_03; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2027_03;


--
-- Name: idx_iep_release_health_2027_04; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2027_04;


--
-- Name: idx_iep_release_health_2027_05; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2027_05;


--
-- Name: idx_iep_release_health_2027_06; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_2027_06;


--
-- Name: idx_iep_release_health_default; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_health_occurred ATTACH PARTITION public.idx_iep_release_health_default;


--
-- Name: ingest_events_partitioned_2026_02_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_02_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_02_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_02_context_idx;


--
-- Name: ingest_events_partitioned_2026_02_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_02_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_02_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_02_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_02_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_02_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_02_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_02_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_02_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_02_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_02_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_02_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_02_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_03_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_03_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_03_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_03_context_idx;


--
-- Name: ingest_events_partitioned_2026_03_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_03_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_03_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_03_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_03_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_03_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_03_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_03_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_03_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_03_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_03_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_03_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_03_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_04_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_04_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_04_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_04_context_idx;


--
-- Name: ingest_events_partitioned_2026_04_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_04_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_04_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_04_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_04_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_04_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_04_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_04_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_04_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_04_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_04_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_04_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_04_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_05_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_05_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_05_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_05_context_idx;


--
-- Name: ingest_events_partitioned_2026_05_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_05_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_05_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_05_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_05_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_05_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_05_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_05_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_05_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_05_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_05_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_05_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_05_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_06_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_06_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_06_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_06_context_idx;


--
-- Name: ingest_events_partitioned_2026_06_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_06_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_06_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_06_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_06_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_06_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_06_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_06_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_06_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_06_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_06_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_06_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_06_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_07_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_07_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_07_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_07_context_idx;


--
-- Name: ingest_events_partitioned_2026_07_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_07_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_07_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_07_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_07_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_07_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_07_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_07_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_07_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_07_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_07_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_07_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_07_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_08_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_08_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_08_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_08_context_idx;


--
-- Name: ingest_events_partitioned_2026_08_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_08_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_08_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_08_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_08_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_08_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_08_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_08_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_08_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_08_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_08_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_08_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_08_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_09_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_09_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_09_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_09_context_idx;


--
-- Name: ingest_events_partitioned_2026_09_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_09_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_09_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_09_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_09_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_09_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_09_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_09_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_09_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_09_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_09_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_09_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_09_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_10_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_10_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_10_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_10_context_idx;


--
-- Name: ingest_events_partitioned_2026_10_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_10_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_10_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_10_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_10_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_10_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_10_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_10_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_10_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_10_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_10_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_10_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_10_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_11_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_11_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_11_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_11_context_idx;


--
-- Name: ingest_events_partitioned_2026_11_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_11_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_11_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_11_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_11_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_11_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_11_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_11_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_11_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_11_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_11_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_11_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_11_uuid_idx;


--
-- Name: ingest_events_partitioned_2026_12_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2026_12_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2026_12_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2026_12_context_idx;


--
-- Name: ingest_events_partitioned_2026_12_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2026_12_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_12_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2026_12_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2026_12_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2026_12_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2026_12_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2026_12_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_idx;


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_12_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_12_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2026_12_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2026_12_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2026_12_uuid_idx;


--
-- Name: ingest_events_partitioned_2026__project_id_expr_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026__project_id_expr_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx4;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx5;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx6;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx7;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx8; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx8;


--
-- Name: ingest_events_partitioned_2026_project_id_expr_occurred_at_idx9; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2026_project_id_expr_occurred_at_idx9;


--
-- Name: ingest_events_partitioned_2027_01_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2027_01_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2027_01_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2027_01_context_idx;


--
-- Name: ingest_events_partitioned_2027_01_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2027_01_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_01_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2027_01_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2027_01_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2027_01_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2027_01_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2027_01_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_idx;


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2027_01_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2027_01_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2027_01_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2027_01_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2027_01_uuid_idx;


--
-- Name: ingest_events_partitioned_2027_02_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2027_02_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2027_02_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2027_02_context_idx;


--
-- Name: ingest_events_partitioned_2027_02_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2027_02_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_02_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2027_02_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2027_02_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2027_02_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2027_02_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2027_02_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_idx;


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2027_02_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2027_02_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2027_02_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2027_02_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2027_02_uuid_idx;


--
-- Name: ingest_events_partitioned_2027_03_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2027_03_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2027_03_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2027_03_context_idx;


--
-- Name: ingest_events_partitioned_2027_03_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2027_03_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_03_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2027_03_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2027_03_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2027_03_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2027_03_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2027_03_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_idx;


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2027_03_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2027_03_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2027_03_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2027_03_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2027_03_uuid_idx;


--
-- Name: ingest_events_partitioned_2027_04_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2027_04_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2027_04_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2027_04_context_idx;


--
-- Name: ingest_events_partitioned_2027_04_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2027_04_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_04_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2027_04_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2027_04_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2027_04_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2027_04_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2027_04_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_idx;


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2027_04_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2027_04_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2027_04_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2027_04_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2027_04_uuid_idx;


--
-- Name: ingest_events_partitioned_2027_05_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2027_05_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2027_05_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2027_05_context_idx;


--
-- Name: ingest_events_partitioned_2027_05_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2027_05_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_05_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2027_05_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2027_05_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2027_05_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2027_05_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2027_05_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_idx;


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2027_05_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2027_05_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2027_05_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2027_05_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2027_05_uuid_idx;


--
-- Name: ingest_events_partitioned_2027_06_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_2027_06_api_key_id_idx;


--
-- Name: ingest_events_partitioned_2027_06_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_2027_06_context_idx;


--
-- Name: ingest_events_partitioned_2027_06_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_2027_06_created_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_06_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_2027_06_error_group_id_idx;


--
-- Name: ingest_events_partitioned_2027_06_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_2027_06_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_2027_06_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_2027_06_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_idx;


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2027_06_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2027_06_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_2027_06_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_2027_06_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_2027_06_uuid_idx;


--
-- Name: ingest_events_partitioned_2027__project_id_expr_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2027__project_id_expr_occurred_at_idx;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx4;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx5;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx6;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx7;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx8; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx8;


--
-- Name: ingest_events_partitioned_2027_project_id_expr_occurred_at_idx9; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_2027_project_id_expr_occurred_at_idx9;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred__idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred__idx;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx1;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx2;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx3;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx4;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx5;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx6;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx7;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx8; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx8;


--
-- Name: ingest_events_partitioned_202_project_id_coalesce_occurred_idx9; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_coalesce_occurred_idx9;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx1;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx2;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx3;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx4;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx5;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx6;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx7;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx8; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx8;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurr_idx9; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurr_idx9;


--
-- Name: ingest_events_partitioned_202_project_id_event_type_occurre_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_202_project_id_event_type_occurre_idx;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx1;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx2;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx3;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx4;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx5;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx6;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx7;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx8; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx8;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at__idx9; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at__idx9;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_i_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_i_idx;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx10; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx10;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx11; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx11;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx12; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx12;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx13; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx13;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx14; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx14;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx15; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx15;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx16; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx16;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx17; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx17;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx18; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx18;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx19; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx19;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx20; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx20;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx21; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx21;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx22; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx22;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx23; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx23;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx24; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx24;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx25; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx25;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx26; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx26;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx27; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx27;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx28; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx28;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx29; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx29;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx30; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx30;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx31; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx31;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx32; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx32;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx33; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx33;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx34; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx34;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx35; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx35;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx36; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx36;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx37; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx37;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx38; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx38;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx39; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx39;


--
-- Name: ingest_events_partitioned_202_project_id_expr_occurred_at_idx40; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_expr_occurred_at_idx40;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx1;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx2;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx3;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx4;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx5;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx6;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx7;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx8; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx8;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred__idx9; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred__idx9;


--
-- Name: ingest_events_partitioned_202_project_id_message_occurred_a_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_202_project_id_message_occurred_a_idx;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx1;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx2;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx3;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx4;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx5;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx6;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx7;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx8; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx8;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_a_idx9; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_a_idx9;


--
-- Name: ingest_events_partitioned_202_project_id_nullif_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_202_project_id_nullif_occurred_at_idx;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx10; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx10;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx11; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx11;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx12; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx12;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx13; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx13;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx14; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx14;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx15; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx15;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx16; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx16;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx17; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx17;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx18; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx18;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx19; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx19;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx20; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx20;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx21; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx21;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx22; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx22;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx23; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx23;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx24; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx24;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx25; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx25;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx26; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx26;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx27; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx27;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx28; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx28;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx29; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx29;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx30; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx30;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx31; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx31;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx32; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx32;


--
-- Name: ingest_events_partitioned_20_project_id_coalesce_occurred_idx33; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_coalesce_occurred_idx33;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx10; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx10;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx11; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx11;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx12; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx12;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx13; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx13;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx14; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx14;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx15; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx15;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx16; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx16;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx17; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx17;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx18; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx18;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx19; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx19;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx20; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx20;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx21; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx21;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx22; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx22;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx23; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx23;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx24; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx24;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx25; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx25;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx26; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx26;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx27; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx27;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx28; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx28;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx29; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx29;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx30; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx30;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx31; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx31;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx32; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx32;


--
-- Name: ingest_events_partitioned_20_project_id_event_type_occurr_idx33; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_20_project_id_event_type_occurr_idx33;


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx10; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_expr_occurred_at__idx10;


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx11; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_expr_occurred_at__idx11;


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx12; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_expr_occurred_at__idx12;


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx13; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_expr_occurred_at__idx13;


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx14; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_expr_occurred_at__idx14;


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx15; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_expr_occurred_at__idx15;


--
-- Name: ingest_events_partitioned_20_project_id_expr_occurred_at__idx16; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_20_project_id_expr_occurred_at__idx16;


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx10; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_20_project_id_message_occurred__idx10;


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx11; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_20_project_id_message_occurred__idx11;


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx12; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_20_project_id_message_occurred__idx12;


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx13; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_20_project_id_message_occurred__idx13;


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx14; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_20_project_id_message_occurred__idx14;


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx15; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_20_project_id_message_occurred__idx15;


--
-- Name: ingest_events_partitioned_20_project_id_message_occurred__idx16; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_20_project_id_message_occurred__idx16;


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx10; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_nullif_occurred_a_idx10;


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx11; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_nullif_occurred_a_idx11;


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx12; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_nullif_occurred_a_idx12;


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx13; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_nullif_occurred_a_idx13;


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx14; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_nullif_occurred_a_idx14;


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx15; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_nullif_occurred_a_idx15;


--
-- Name: ingest_events_partitioned_20_project_id_nullif_occurred_a_idx16; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_20_project_id_nullif_occurred_a_idx16;


--
-- Name: ingest_events_partitioned_def_project_id_coalesce_occurred__idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_env_cursor ATTACH PARTITION public.ingest_events_partitioned_def_project_id_coalesce_occurred__idx;


--
-- Name: ingest_events_partitioned_def_project_id_coalesce_occurred_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_environment_occurred ATTACH PARTITION public.ingest_events_partitioned_def_project_id_coalesce_occurred_idx1;


--
-- Name: ingest_events_partitioned_def_project_id_event_type_occurr_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_type_retention ATTACH PARTITION public.ingest_events_partitioned_def_project_id_event_type_occurr_idx1;


--
-- Name: ingest_events_partitioned_def_project_id_event_type_occurre_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_occurred_type ATTACH PARTITION public.ingest_events_partitioned_def_project_id_event_type_occurre_idx;


--
-- Name: ingest_events_partitioned_def_project_id_expr_occurred_at_i_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_release_cursor ATTACH PARTITION public.ingest_events_partitioned_def_project_id_expr_occurred_at_i_idx;


--
-- Name: ingest_events_partitioned_def_project_id_message_occurred_a_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_metric_message ATTACH PARTITION public.ingest_events_partitioned_def_project_id_message_occurred_a_idx;


--
-- Name: ingest_events_partitioned_def_project_id_nullif_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_release_occurred ATTACH PARTITION public.ingest_events_partitioned_def_project_id_nullif_occurred_at_idx;


--
-- Name: ingest_events_partitioned_defa_project_id_expr_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_platform_occurred ATTACH PARTITION public.ingest_events_partitioned_defa_project_id_expr_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_defa_project_id_expr_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_service_occurred ATTACH PARTITION public.ingest_events_partitioned_defa_project_id_expr_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_defau_project_id_expr_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_cf_pages_deployment ATTACH PARTITION public.ingest_events_partitioned_defau_project_id_expr_occurred_at_idx;


--
-- Name: ingest_events_partitioned_default_api_key_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_api_key_id ATTACH PARTITION public.ingest_events_partitioned_default_api_key_id_idx;


--
-- Name: ingest_events_partitioned_default_context_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_context_path_ops ATTACH PARTITION public.ingest_events_partitioned_default_context_idx;


--
-- Name: ingest_events_partitioned_default_created_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_retention_created ATTACH PARTITION public.ingest_events_partitioned_default_created_at_id_idx;


--
-- Name: ingest_events_partitioned_default_error_group_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_error_group_id ATTACH PARTITION public.ingest_events_partitioned_default_error_group_id_idx;


--
-- Name: ingest_events_partitioned_default_id_occurred_at_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.ingest_events_partitioned_id_occurred_at_key ATTACH PARTITION public.ingest_events_partitioned_default_id_occurred_at_key;


--
-- Name: ingest_events_partitioned_default_project_id_event_type_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_type ATTACH PARTITION public.ingest_events_partitioned_default_project_id_event_type_idx;


--
-- Name: ingest_events_partitioned_default_project_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_id ATTACH PARTITION public.ingest_events_partitioned_default_project_id_idx;


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_cursor ATTACH PARTITION public.ingest_events_partitioned_default_project_id_occurred_at_id_idx;


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_activity_occurred ATTACH PARTITION public.ingest_events_partitioned_default_project_id_occurred_at_idx;


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_db_query_occurred ATTACH PARTITION public.ingest_events_partitioned_default_project_id_occurred_at_idx1;


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_transactions ATTACH PARTITION public.ingest_events_partitioned_default_project_id_occurred_at_idx2;


--
-- Name: ingest_events_partitioned_default_project_id_occurred_at_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_project_occurred ATTACH PARTITION public.ingest_events_partitioned_default_project_id_occurred_at_idx3;


--
-- Name: ingest_events_partitioned_default_project_id_updated_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_ingest_events_part_updated_at ATTACH PARTITION public.ingest_events_partitioned_default_project_id_updated_at_idx;


--
-- Name: ingest_events_partitioned_default_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_ingest_events_part_uuid ATTACH PARTITION public.ingest_events_partitioned_default_uuid_idx;


--
-- Name: ingest_events logister_ingest_events_partition_mirror; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER logister_ingest_events_partition_mirror AFTER INSERT OR DELETE OR UPDATE ON public.ingest_events FOR EACH ROW EXECUTE FUNCTION public.logister_mirror_ingest_event_to_partitioned();


--
-- Name: ingest_events_partitioned fk_ingest_events_partitioned_api_keys; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.ingest_events_partitioned
    ADD CONSTRAINT fk_ingest_events_partitioned_api_keys FOREIGN KEY (api_key_id) REFERENCES public.api_keys(id);


--
-- Name: ingest_events_partitioned fk_ingest_events_partitioned_error_groups; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.ingest_events_partitioned
    ADD CONSTRAINT fk_ingest_events_partitioned_error_groups FOREIGN KEY (error_group_id) REFERENCES public.error_groups(id);


--
-- Name: ingest_events_partitioned fk_ingest_events_partitioned_projects; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.ingest_events_partitioned
    ADD CONSTRAINT fk_ingest_events_partitioned_projects FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: project_source_repositories fk_rails_050fdd9552; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_source_repositories
    ADD CONSTRAINT fk_rails_050fdd9552 FOREIGN KEY (github_installation_id) REFERENCES public.github_installations(id);


--
-- Name: api_keys fk_rails_05cc5a9e37; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT fk_rails_05cc5a9e37 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: mobile_ingest_tokens fk_rails_0bc57896ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mobile_ingest_tokens
    ADD CONSTRAINT fk_rails_0bc57896ad FOREIGN KEY (project_id) REFERENCES public.projects(id);

--
-- Name: email_notification_deliveries fk_rails_0bf84f58c1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_notification_deliveries
    ADD CONSTRAINT fk_rails_0bf84f58c1 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: error_groups fk_rails_0c893a4445; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT fk_rails_0c893a4445 FOREIGN KEY (assigned_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: project_memberships fk_rails_18b611e244; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_memberships
    ADD CONSTRAINT fk_rails_18b611e244 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: project_deployments fk_rails_1f89aeb07e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_deployments
    ADD CONSTRAINT fk_rails_1f89aeb07e FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: project_notification_preferences fk_rails_2c7979b0ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_notification_preferences
    ADD CONSTRAINT fk_rails_2c7979b0ad FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: error_groups fk_rails_2d081e8402; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT fk_rails_2d081e8402 FOREIGN KEY (latest_event_id) REFERENCES public.ingest_events(id);


--
-- Name: error_groups fk_rails_2e1f89a5fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT fk_rails_2e1f89a5fa FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: email_notification_deliveries fk_rails_3155e737db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_notification_deliveries
    ADD CONSTRAINT fk_rails_3155e737db FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: api_keys fk_rails_32c28d0dc2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT fk_rails_32c28d0dc2 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: project_source_repositories fk_rails_3e5e3e3141; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_source_repositories
    ADD CONSTRAINT fk_rails_3e5e3e3141 FOREIGN KEY (github_repository_id) REFERENCES public.github_repositories(id);


--
-- Name: trace_spans fk_rails_401b288d25; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trace_spans
    ADD CONSTRAINT fk_rails_401b288d25 FOREIGN KEY (api_key_id) REFERENCES public.api_keys(id);


--
-- Name: github_repositories fk_rails_4b5b7ee569; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_repositories
    ADD CONSTRAINT fk_rails_4b5b7ee569 FOREIGN KEY (github_installation_id) REFERENCES public.github_installations(id);


--
-- Name: github_installations fk_rails_4d0e25c6f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_installations
    ADD CONSTRAINT fk_rails_4d0e25c6f8 FOREIGN KEY (installed_by_id) REFERENCES public.users(id);


--
-- Name: project_deployments fk_rails_5cf5091a89; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_deployments
    ADD CONSTRAINT fk_rails_5cf5091a89 FOREIGN KEY (project_source_repository_id) REFERENCES public.project_source_repositories(id);


--
-- Name: ingest_events fk_rails_63e91c7aa9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events
    ADD CONSTRAINT fk_rails_63e91c7aa9 FOREIGN KEY (error_group_id) REFERENCES public.error_groups(id);


--
-- Name: project_github_installations fk_rails_65890f22d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_installations
    ADD CONSTRAINT fk_rails_65890f22d9 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: email_notification_deliveries fk_rails_73897ec334; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_notification_deliveries
    ADD CONSTRAINT fk_rails_73897ec334 FOREIGN KEY (error_group_id) REFERENCES public.error_groups(id);


--
-- Name: error_group_external_links fk_rails_7624c0ac28; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_group_external_links
    ADD CONSTRAINT fk_rails_7624c0ac28 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: ingest_events fk_rails_7af152c71f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events
    ADD CONSTRAINT fk_rails_7af152c71f FOREIGN KEY (api_key_id) REFERENCES public.api_keys(id);


--
-- Name: project_retention_policies fk_rails_81cdd6d032; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_retention_policies
    ADD CONSTRAINT fk_rails_81cdd6d032 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: project_memberships fk_rails_86b046ec96; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_memberships
    ADD CONSTRAINT fk_rails_86b046ec96 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: error_group_external_links fk_rails_8e4514ec2a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_group_external_links
    ADD CONSTRAINT fk_rails_8e4514ec2a FOREIGN KEY (error_group_id) REFERENCES public.error_groups(id);


--
-- Name: trace_spans fk_rails_901bab7c48; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trace_spans
    ADD CONSTRAINT fk_rails_901bab7c48 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: error_groups fk_rails_a1ec8ce518; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT fk_rails_a1ec8ce518 FOREIGN KEY (assigned_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: error_group_external_links fk_rails_a3a36eaa76; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_group_external_links
    ADD CONSTRAINT fk_rails_a3a36eaa76 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: project_github_installations fk_rails_a87135db59; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_installations
    ADD CONSTRAINT fk_rails_a87135db59 FOREIGN KEY (github_installation_id) REFERENCES public.github_installations(id);


--
-- Name: ingest_events fk_rails_ada86cb38d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingest_events
    ADD CONSTRAINT fk_rails_ada86cb38d FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: error_occurrences fk_rails_b004382b7c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_occurrences
    ADD CONSTRAINT fk_rails_b004382b7c FOREIGN KEY (ingest_event_id) REFERENCES public.ingest_events(id);


--
-- Name: project_deployments fk_rails_b1f64fa257; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_deployments
    ADD CONSTRAINT fk_rails_b1f64fa257 FOREIGN KEY (github_repository_id) REFERENCES public.github_repositories(id);


--
-- Name: projects fk_rails_b872a6760a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_b872a6760a FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: project_integration_settings fk_rails_c86e5b4a54; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_integration_settings
    ADD CONSTRAINT fk_rails_c86e5b4a54 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: project_notification_preferences fk_rails_c997cb59bb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_notification_preferences
    ADD CONSTRAINT fk_rails_c997cb59bb FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: project_github_installations fk_rails_ce98bc6cb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_installations
    ADD CONSTRAINT fk_rails_ce98bc6cb1 FOREIGN KEY (linked_by_id) REFERENCES public.users(id);


--
-- Name: check_in_monitors fk_rails_d3835f8871; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_in_monitors
    ADD CONSTRAINT fk_rails_d3835f8871 FOREIGN KEY (last_event_id) REFERENCES public.ingest_events(id);


--
-- Name: error_occurrences fk_rails_d7c10605c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_occurrences
    ADD CONSTRAINT fk_rails_d7c10605c5 FOREIGN KEY (error_group_id) REFERENCES public.error_groups(id);


--
-- Name: telemetry_archives fk_rails_d7de98b3b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_archives
    ADD CONSTRAINT fk_rails_d7de98b3b0 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: project_source_repositories fk_rails_dd26daa789; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_source_repositories
    ADD CONSTRAINT fk_rails_dd26daa789 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: check_in_monitors fk_rails_f305160af5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_in_monitors
    ADD CONSTRAINT fk_rails_f305160af5 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: cli_device_authorizations fk_rails_57e8eeff05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cli_device_authorizations
    ADD CONSTRAINT fk_rails_57e8eeff05 FOREIGN KEY (cli_access_token_id) REFERENCES public.cli_access_tokens(id);


--
-- Name: cli_access_tokens fk_rails_d295f5f850; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cli_access_tokens
    ADD CONSTRAINT fk_rails_d295f5f850 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: cli_device_authorizations fk_rails_f74cfc2adf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cli_device_authorizations
    ADD CONSTRAINT fk_rails_f74cfc2adf FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: mobile_ingest_tokens fk_rails_f599113ac4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mobile_ingest_tokens
    ADD CONSTRAINT fk_rails_f599113ac4 FOREIGN KEY (api_key_id) REFERENCES public.api_keys(id);

--
-- Name: user_notification_dismissals fk_rails_feaaa03c25; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_notification_dismissals
    ADD CONSTRAINT fk_rails_feaaa03c25 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260701193000'),
('20260701190000'),
('20260620183000'),
('20260620180000'),
('20260618170000'),
('20260618161000'),
('20260618152000'),
('20260618150000'),
('20260618143000'),
('20260618142000'),
('20260618141000'),
('20260618140000'),
('20260613133000'),
('20260613124500'),
('20260613123000'),
('20260613120000'),
('20260601223000'),
('20260601221000'),
('20260523210500'),
('20260523120000'),
('20260522234000'),
('20260522231500'),
('20260522224500'),
('20260522223000'),
('20260522210000'),
('20260521201500'),
('20260521195000'),
('20260521153000'),
('20260510171000'),
('20260510170000'),
('20260510163000'),
('20260510161000'),
('20260510154000'),
('20260510150000'),
('20260509120001'),
('20260509120000'),
('20260421185034'),
('20260417113000'),
('20260417110000'),
('20260302100000'),
('20260226120002'),
('20260226120001'),
('20260226120000'),
('20260215093000'),
('20260215084500'),
('20260215081500'),
('20260215074500'),
('20260215060000'),
('20260215025031'),
('20260215025030'),
('20260215025029'),
('20260215025023');
