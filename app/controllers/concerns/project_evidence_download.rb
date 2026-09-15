# frozen_string_literal: true

require "openssl"

module ProjectEvidenceDownload
  def original_evidence
    reason = params[:reason].to_s.strip
    audit = @project.evidence_access_audits.new(
      user: current_user,
      ingest_event_uuid: @event.uuid,
      ingest_event_occurred_at: @event.occurred_at,
      action: "download_unredacted_stored_evidence",
      reason: reason,
      request_metadata: {
        "ip_hmac" => evidence_request_ip_hmac,
        "user_agent" => request.user_agent.to_s.first(300)
      }.compact
    )
    unless audit.save
      return render json: { errors: audit.errors.full_messages }, status: :unprocessable_content
    end

    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data(
      JSON.pretty_generate(
        {
          "evidence_access" => {
            "audit_uuid" => audit.uuid,
            "project_uuid" => @project.uuid,
            "event_uuid" => @event.uuid,
            "event_occurred_at" => @event.occurred_at.utc.iso8601(6),
            "exported_at" => Time.current.utc.iso8601(6),
            "representation" => "stored_unredacted_context",
            "wire_original" => false
          },
          "context" => @event.context.as_json
        }
      ),
      filename: "logister-evidence-#{@event.uuid}.json",
      type: "application/json; charset=utf-8",
      disposition: "attachment"
    )
  end

  private

  def evidence_request_ip_hmac
    value = request.remote_ip.to_s
    return if value.blank?

    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "evidence-access-ip:#{value}")
  end
end
