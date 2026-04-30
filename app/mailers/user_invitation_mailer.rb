class UserInvitationMailer < ApplicationMailer
  def invite(invitation_payload = nil, **kwargs)
    payload = invitation_payload.respond_to?(:to_h) ? invitation_payload.to_h : {}
    invitation_id =
      kwargs[:invitation_id] ||
      kwargs["invitation_id"] ||
      payload[:invitation_id] ||
      payload["invitation_id"]

    Rails.logger.warn(
      "Skipping retired user invitation email " \
      "for invitation_id=#{invitation_id.inspect}"
    )

    mail(to: fallback_recipient, subject: "Retired Logister invitation") do |format|
      format.text { render plain: "This Logister invitation flow has been retired." }
    end.tap { |message| message.perform_deliveries = false }
  end

  private

  def fallback_recipient
    ENV.fetch("LOGISTER_EMAIL_FROM", "support@logister.org")
  end
end
