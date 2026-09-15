# frozen_string_literal: true

module Api::V1::IngestEventBatches
  BATCH_CONTENT_TYPES = %w[application/x-ndjson application/ndjson].freeze

  def batch
    return render_unsupported_batch_content_type unless BATCH_CONTENT_TYPES.include?(request.media_type)

    raw_events = decode_batch_events
    return if consume_additional_batch_volume!(raw_events.length)

    prepared = raw_events.each_with_index.map { |event, index| prepare_batch_event(event, index) }
    prepared.each do |entry|
      return unless enforce_mobile_ingest_token_scope!(
        event_type: entry.fetch(:event_type),
        context: entry.fetch(:attributes).fetch(:context)
      )
    end

    acceptance = Logister::TelemetryBatchAcceptance.new(
      project: @api_key.project,
      api_key: @api_key,
      entries: prepared,
      request_context: request_context
    ).call
    results = acceptance.entries.map { |result| batch_result(result.fetch(:entry), result) }

    if acceptance.rejected?
      render_rejected_batch(results)
    else
      touch_client_submission_credential!
      enqueue_batch_projection(acceptance.outbox_events)
      render json: {
        schema_version: 1,
        batch_id: submitted_batch_id,
        status: "accepted",
        accepted: results.length,
        duplicates: results.count { |result| result[:duplicate] },
        results: results
      }.compact, status: :accepted
    end
  end

  private

  def decode_batch_events
    request.body.rewind if request.body.respond_to?(:rewind)
    TelemetryBatchDecoder.call(
      io: request.body,
      content_encoding: request.headers["Content-Encoding"]
    )
  end

  def prepare_batch_event(event, index)
    normalizer = IngestEventPayloadNormalizer.new(
      params: ActionController::Parameters.new(event: event),
      default_environment: default_event_environment
    )
    raw_event = normalizer.event_hash
    span = normalizer.span_payload?(raw_event)
    attributes = span ? normalizer.trace_span_params(raw_event) : normalizer.event_params(raw_event)

    {
      index: index,
      type: span ? "span" : "event",
      event_type: span ? "span" : attributes["event_type"].to_s,
      attributes: attributes
    }
  end

  def batch_result(entry, result)
    record = result.fetch(:record)
    return {
      index: entry.fetch(:index),
      status: "rejected",
      type: entry.fetch(:type),
      errors: record.errors.full_messages
    } unless result.fetch(:accepted)

    {
      index: entry.fetch(:index),
      status: "accepted",
      type: entry.fetch(:type),
      id: record.uuid,
      legacy_id: record.id,
      duplicate: result.fetch(:duplicate)
    }
  end

  def render_rejected_batch(results)
    normalized_results = results.map do |result|
      next result if result[:status] == "rejected" || result[:duplicate]

      result.except(:id, :legacy_id, :duplicate).merge(
        status: "rolled_back",
        errors: [ "Batch was rolled back because another envelope was invalid" ]
      )
    end
    errors = normalized_results.flat_map { |result| Array(result[:errors]) }
    report_client_submission_failure(
      reason: "invalid_batch",
      status: :unprocessable_content,
      errors: errors
    )
    render json: {
      schema_version: 1,
      batch_id: submitted_batch_id,
      status: "rejected",
      results: normalized_results
    }.compact, status: :unprocessable_content
  end

  def enqueue_batch_projection(outbox_events)
    outbox_ids = outbox_events.filter_map(&:id)
    return if outbox_ids.empty?
    return unless TelemetryDelivery.where(telemetry_outbox_event_id: outbox_ids).incomplete.exists?

    TelemetryProjectorJob.wake!
  rescue StandardError => error
    Rails.logger.error("telemetry_batch_projector_enqueue_error error=#{error.class}: #{error.message}")
  end

  def consume_additional_batch_volume!(event_count)
    additional = event_count.to_i - 1
    return false unless additional.positive?

    project = @api_key.project
    identity = if mobile_ingest_token?
      "mobile_ingest_token:#{@mobile_ingest_token.id}"
    else
      "api_key:#{@api_key.id}"
    end
    limited = public_api_rate_limited?(
      identity: identity,
      kind: "accepted",
      limit: public_api_rate_limit_requests(project),
      period: public_api_rate_limit_period_seconds(project),
      amount: additional
    )
    render_public_api_rate_limited if limited
    limited
  end

  def submitted_batch_id
    request.headers["X-Logister-Batch-Id"].to_s.first(128).presence
  end

  def render_unsupported_batch_content_type
    render json: {
      error: "Batch ingest requires application/x-ndjson",
      code: "unsupported_content_type"
    }, status: :unsupported_media_type
  end

  def render_invalid_batch(error)
    status = if error.code.in?(%i[compressed_bytes decompressed_bytes event_count])
      :content_too_large
    elsif error.code == :unsupported_encoding
      :unsupported_media_type
    else
      :bad_request
    end
    report_client_submission_failure(
      reason: error.code,
      status: status,
      exception: error
    )
    render json: { error: error.message, code: error.code }, status: status
  end
end
