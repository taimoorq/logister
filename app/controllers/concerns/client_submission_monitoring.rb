module ClientSubmissionMonitoring
  extend ActiveSupport::Concern

  private

  def authenticate_api_key!
    token = submitted_api_key_token
    @api_key = ApiKey.authenticate(token)
    if @api_key
      project = @api_key.project
      return unless public_api_rate_limited?(
        identity: "api_key:#{@api_key.id}",
        kind: "accepted",
        limit: public_api_rate_limit_requests(project),
        period: public_api_rate_limit_period_seconds(project)
      )

      return render_public_api_rate_limited
    end

    diagnostic_api_key = diagnostic_api_key_for(token)
    diagnostic_project = diagnostic_api_key&.project
    if public_api_rate_limited?(
      identity: "ip:#{request.remote_ip.presence || 'unknown'}",
      kind: "auth_failure",
      limit: public_api_auth_failure_rate_limit_requests(diagnostic_project),
      period: public_api_rate_limit_period_seconds(diagnostic_project)
    )
      return render_public_api_rate_limited
    end

    report_client_submission_failure(
      reason: auth_failure_reason(token, diagnostic_api_key),
      status: :unauthorized,
      api_key: diagnostic_api_key,
      token: token
    )

    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def public_api_rate_limited?(identity:, kind:, limit:, period:)
    limit = limit.to_i
    return false unless limit.positive?

    period = period.to_i
    return false unless period.positive?

    window_started_at = Time.current.to_i / period * period
    reset_at = window_started_at + period
    count = public_api_rate_limit_count(kind, identity, window_started_at, period)
    return false unless count

    set_public_api_rate_limit_headers(limit, count, reset_at)
    @public_api_rate_limit_context = {
      limit: limit,
      remaining: [ limit - count, 0 ].max,
      reset_at: reset_at,
      retry_after: public_api_retry_after(reset_at),
      window_seconds: period
    }
    count > limit
  rescue StandardError => error
    Rails.logger.warn("public API rate limiting skipped: #{error.class} #{error.message}")
    false
  end

  def public_api_rate_limit_count(kind, identity, window_started_at, period)
    cache_key = public_api_rate_limit_cache_key(kind, identity, window_started_at)
    count = Rails.cache.increment(cache_key, 1, expires_in: period + 5)
    return count if count

    Rails.cache.write(cache_key, 1, expires_in: period + 5)
    1
  end

  def public_api_rate_limit_cache_key(kind, identity, window_started_at)
    endpoint = kind == "auth_failure" ? "all" : client_submission_endpoint_label
    identity_digest = Digest::SHA256.hexdigest(identity.to_s)
    "logister:public_api_rate_limit:v1:#{kind}:#{endpoint}:#{identity_digest}:#{window_started_at}"
  end

  def render_public_api_rate_limited
    context = @public_api_rate_limit_context || {
      limit: public_api_rate_limit_requests(nil),
      remaining: 0,
      reset_at: Time.current.to_i + public_api_rate_limit_period_seconds(nil),
      retry_after: public_api_rate_limit_period_seconds(nil),
      window_seconds: public_api_rate_limit_period_seconds(nil)
    }

    response.set_header("Retry-After", context[:retry_after].to_s)
    render json: {
      error: "Rate limit exceeded",
      limit: context[:limit],
      window_seconds: context[:window_seconds],
      retry_after: context[:retry_after]
    }, status: :too_many_requests
  end

  def set_public_api_rate_limit_headers(limit, count, reset_at)
    response.set_header("X-RateLimit-Limit", limit.to_s)
    response.set_header("X-RateLimit-Remaining", [ limit - count, 0 ].max.to_s)
    response.set_header("X-RateLimit-Reset", reset_at.to_s)
  end

  def public_api_retry_after(reset_at)
    [ reset_at - Time.current.to_i, 1 ].max
  end

  def public_api_rate_limit_requests(project)
    default = Project.default_public_api_rate_limit_requests
    return default unless project

    project.public_api_rate_limit_requests_effective(default)
  end

  def public_api_auth_failure_rate_limit_requests(project)
    default = Project.default_public_api_auth_failure_rate_limit_requests
    return default unless project

    project.public_api_auth_failure_rate_limit_requests_effective(default)
  end

  def public_api_rate_limit_period_seconds(project)
    default = Project.default_public_api_rate_limit_period_seconds
    return default unless project

    project.public_api_rate_limit_period_seconds_effective(default)
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
