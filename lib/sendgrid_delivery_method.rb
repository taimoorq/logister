require "sendgrid-ruby"

class SendgridDeliveryMethod
  include SendGrid

  def initialize(options = {})
    @api_key = options[:api_key] || ENV["SENDGRID_API_KEY"]
  end

  def deliver!(mail)
    raise "Missing SENDGRID_API_KEY" if @api_key.blank?

    payload = SendGrid::Mail.new
    payload.from = SendGrid::Email.new(email: from_address(mail))
    payload.subject = mail.subject.to_s

    personalization = SendGrid::Personalization.new
    each_address(mail.to) { |email| personalization.add_to(SendGrid::Email.new(email: email)) }
    each_address(mail.cc) { |email| personalization.add_cc(SendGrid::Email.new(email: email)) }
    each_address(mail.bcc) { |email| personalization.add_bcc(SendGrid::Email.new(email: email)) }
    payload.add_personalization(personalization)

    reply_to = first_address(mail.reply_to)
    payload.reply_to = SendGrid::Email.new(email: reply_to) if reply_to.present?

    add_content_parts(payload, mail)

    response = SendGrid::API.new(api_key: @api_key).client.mail._("send").post(request_body: payload.to_json)
    return if response.status_code.to_i.between?(200, 299)

    raise "SendGrid API error: #{response.status_code} #{response.body}"
  end

  private

  def add_content_parts(payload, mail)
    if mail.html_part
      payload.add_content(SendGrid::Content.new(type: "text/html", value: mail.html_part.decoded))
    end

    if mail.text_part
      payload.add_content(SendGrid::Content.new(type: "text/plain", value: mail.text_part.decoded))
    elsif !mail.html_part
      type = mail.mime_type.to_s.include?("html") ? "text/html" : "text/plain"
      payload.add_content(SendGrid::Content.new(type: type, value: mail.body.decoded))
    end
  end

  def from_address(mail)
    first_address(mail.from) || ENV.fetch("LOGISTER_EMAIL_FROM", "support@logister.org")
  end

  def each_address(list)
    Array(list).each do |raw|
      parsed = Mail::Address.new(raw.to_s)
      yield(parsed.address) if parsed.address.present?
    rescue Mail::Field::ParseError
      next
    end
  end

  def first_address(list)
    result = nil
    each_address(list) { |email| result ||= email }
    result
  end
end
