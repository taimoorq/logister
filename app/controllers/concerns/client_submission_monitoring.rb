module ClientSubmissionMonitoring
  extend ActiveSupport::Concern

  private

  def authenticate_api_key!
    token = submitted_api_key_token
    @api_key = ApiKey.authenticate(token)
    return if @api_key

    diagnostic_api_key = diagnostic_api_key_for(token)
    report_client_submission_failure(
      reason: auth_failure_reason(token, diagnostic_api_key),
      status: :unauthorized,
      api_key: diagnostic_api_key,
      token: token
    )

    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def report_client_submission_failure(
    reason:,
    status:,
    errors: nil,
    exception: nil,
    api_key: @api_key,
    token: submitted_api_key_token
  )
    return if client_submission_monitoring_payload?

    status_code = response_status_code(status)

    Logister.report_log(
      message: "Client #{client_submission_endpoint_label} rejected",
      level: "warn",
      fingerprint: "client-submission:#{client_submission_endpoint_label}:#{reason}",
      context: {
        client_submission: {
          reason: reason,
          status: status_code,
          endpoint: client_submission_endpoint_label,
          path: request.path,
          method: request.request_method,
          request_id: request.request_id,
          client_ip: request.remote_ip,
          user_agent: request.user_agent,
          content_type: request.content_type,
          content_length: request.content_length,
          auth: client_submission_auth_context(token),
          project: client_submission_project_context(api_key&.project),
          api_key: client_submission_api_key_context(api_key),
          payload: client_submission_payload_summary,
          errors: Array(errors).presence,
          exception: exception && {
            class: exception.class.name,
            message: exception.message
          }
        }.compact
      }
    )
  rescue StandardError => report_error
    Rails.logger.warn("client submission monitoring failed: #{report_error.class} #{report_error.message}")
  end

  def submitted_api_key_token
    authorization = request.headers["Authorization"].to_s
    if authorization.start_with?("Bearer ")
      @client_submission_token_source = "authorization_bearer"
      return authorization.delete_prefix("Bearer ").strip
    end

    x_api_key = request.headers["X-Api-Key"].to_s
    if x_api_key.present?
      @client_submission_token_source = "x_api_key"
      return x_api_key.strip
    end

    @client_submission_token_source = nil
    nil
  end

  def diagnostic_api_key_for(token)
    return nil if token.blank?

    ApiKey.includes(:project).find_by(token_digest: ApiKey.digest(token))
  end

  def auth_failure_reason(token, api_key)
    return "missing_api_key" if token.blank?
    return "invalid_api_key" unless api_key
    return "revoked_api_key" if api_key.revoked_at.present?
    return "archived_project" if api_key.project&.archived?

    "inactive_api_key"
  end

  def client_submission_auth_context(token)
    authorization = request.headers["Authorization"].to_s

    {
      authorization_header_present: authorization.present?,
      authorization_scheme: authorization.split.first,
      bearer_present: authorization.start_with?("Bearer "),
      x_api_key_present: request.headers["X-Api-Key"].present?,
      token_source: @client_submission_token_source,
      token_digest_prefix: token.present? ? ApiKey.digest(token)[0, 16] : nil
    }.compact
  end

  def client_submission_project_context(project)
    return nil unless project

    {
      uuid: project.uuid,
      slug: project.slug,
      name: project.name,
      integration_kind: project.integration_kind,
      archived: project.archived?,
      archived_at: project.archived_at&.iso8601
    }.compact
  end

  def client_submission_api_key_context(api_key)
    return nil unless api_key

    {
      uuid: api_key.uuid,
      name: api_key.name,
      active: api_key.active?,
      revoked_at: api_key.revoked_at&.iso8601,
      last_used_at: api_key.last_used_at&.iso8601
    }.compact
  end

  def client_submission_payload_summary
    raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    root_keys = raw_params.keys.map(&:to_s).reject { |key| key.in?(%w[controller action]) }
    envelope_key = client_submission_envelope_key(raw_params)
    envelope = envelope_key ? raw_params[envelope_key] : nil
    envelope = envelope.to_unsafe_h if envelope.respond_to?(:to_unsafe_h)

    summary = {
      root_keys: root_keys.sort,
      envelope_key: envelope_key
    }

    return summary.compact unless envelope.is_a?(Hash)

    envelope_keys = envelope.keys.map(&:to_s)
    context = envelope_value(envelope, "context")
    context = context.to_unsafe_h if context.respond_to?(:to_unsafe_h)

    summary.merge(
      envelope_keys: envelope_keys.sort,
      normalized_envelope_keys: envelope_keys.map { |key| submission_normalized_key(key) }.uniq.sort,
      envelope_key_case: envelope_key_case(envelope_key, envelope_keys),
      event_type: envelope_value(envelope, "event_type"),
      level: envelope_value(envelope, "level"),
      message_present: envelope_value(envelope, "message").present?,
      check_in_slug: envelope_value(envelope, "slug"),
      check_in_status: envelope_value(envelope, "status"),
      context_keys: context.is_a?(Hash) ? context.keys.map { |key| submission_normalized_key(key) }.uniq.sort : nil
    ).compact
  end

  def client_submission_envelope_key(raw_params)
    candidate_keys = client_submission_expected_envelope_keys
    raw_params.keys.map(&:to_s).find { |key| candidate_keys.include?(key) }
  end

  def client_submission_expected_envelope_keys
    case client_submission_endpoint_label
    when "check_in"
      %w[check_in CHECK_IN]
    else
      %w[event EVENT]
    end
  end

  def client_submission_endpoint_label
    controller_path.end_with?("check_ins") ? "check_in" : "ingest"
  end

  def envelope_value(envelope, key)
    normalized_key = submission_normalized_key(key)
    pair = envelope.find { |candidate_key, _value| submission_normalized_key(candidate_key) == normalized_key }
    pair&.last
  end

  def client_submission_monitoring_payload?
    raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    envelope_key = client_submission_envelope_key(raw_params)
    envelope = envelope_key ? raw_params[envelope_key] : nil
    envelope = envelope.to_unsafe_h if envelope.respond_to?(:to_unsafe_h)
    return false unless envelope.is_a?(Hash)
    return false unless envelope_value(envelope, "event_type").to_s == "log"
    return false unless envelope_value(envelope, "message").to_s.start_with?("Client ")

    context = envelope_value(envelope, "context")
    context = context.to_unsafe_h if context.respond_to?(:to_unsafe_h)
    context.is_a?(Hash) && envelope_value(context, "client_submission").present?
  end

  def envelope_key_case(envelope_key, envelope_keys)
    keys = [ envelope_key, *envelope_keys ].compact
    return nil if keys.blank?
    return "uppercase" if keys.all? { |key| key == key.upcase }
    return "lowercase" if keys.all? { |key| key == key.downcase }

    "mixed"
  end

  def submission_normalized_key(key)
    key.to_s.underscore.downcase
  end

  def response_status_code(status)
    Rack::Utils.status_code(status)
  rescue StandardError
    status.to_i
  end
end
