# frozen_string_literal: true

require "digest"

# Persists client events and treats a client-supplied UUID as an idempotency key.
# MetricKit can redeliver a diagnostic, so this prevents retries from inflating
# occurrence, installation, and session impact. The transaction-scoped advisory
# lock closes the concurrent-request race that application-level validation
# cannot close on a range-partitioned table.
class IngestEventPersistence
  Result = Data.define(:event, :duplicate?)
  LOCK_TYPE = ActiveRecord::Type::BigInteger.new
  UUID_PATTERN = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

  def initialize(project:, api_key:, attributes:)
    @project = project
    @api_key = api_key
    @attributes = attributes
  end

  def call
    return invalid_uuid_result if raw_client_uuid.present? && client_uuid.blank?
    return persist unless client_uuid.present?

    result = nil
    IngestEvent.transaction(requires_new: true) do
      acquire_idempotency_lock
      existing = project.ingest_events.find_by(uuid: client_uuid)
      result = existing ? Result.new(existing, true) : persist
    end
    result
  end

  private

  attr_reader :project, :api_key, :attributes

  def client_uuid
    return @client_uuid if defined?(@client_uuid)

    @client_uuid = raw_client_uuid if UUID_PATTERN.match?(raw_client_uuid.to_s)
  end

  def raw_client_uuid
    @raw_client_uuid ||= attributes["uuid"].to_s.strip.presence
  end

  def invalid_uuid_result
    event = project.ingest_events.new(attributes.except("uuid"))
    event.api_key = api_key
    event.errors.add(:uuid, "is invalid")
    Result.new(event, false)
  end

  def persist
    event = project.ingest_events.new(attributes)
    event.api_key = api_key
    event.occurred_at ||= Time.current
    event.save
    Result.new(event, false)
  end

  def acquire_idempotency_lock
    connection = ActiveRecord::Base.connection
    return unless connection.adapter_name.downcase.include?("postgresql")

    key = Digest::SHA256.digest("logister:ingest_event:#{project.id}:#{client_uuid}").unpack1("q>")
    bind = ActiveRecord::Relation::QueryAttribute.new("ingest_event_lock_key", key, LOCK_TYPE)
    connection.select_value("SELECT 1 FROM pg_advisory_xact_lock($1)", "IngestEventPersistence", [ bind ])
  end
end
