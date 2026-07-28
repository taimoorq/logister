# frozen_string_literal: true

module CliDeviceAuthorizationIssuing
  def issue!(client_name:, requested_scopes: CliAccessToken::READ_SCOPES, expires_in: CliDeviceAuthorization::DEFAULT_EXPIRES_IN)
    device_code = SecureRandom.urlsafe_base64(48)
    user_code = unique_user_code

    create!(
      device_code_digest: digest(device_code),
      user_code_digest: digest(normalize_user_code(user_code)),
      user_code_display: user_code,
      client_name: client_name,
      requested_scopes: requested_scopes,
      expires_at: expires_in.from_now
    ).tap do |authorization|
      authorization.instance_variable_set(:@plain_device_code, device_code)
    end
  end

  def find_by_device_code(device_code)
    find_by(device_code_digest: digest(device_code))
  end

  def find_by_user_code(user_code)
    find_by(user_code_digest: digest(normalize_user_code(user_code)))
  end

  def digest(value)
    Digest::SHA256.hexdigest(value.to_s)
  end

  def normalize_user_code(value)
    value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  private

  def unique_user_code
    10.times do
      code = generated_user_code
      return code unless exists?(user_code_digest: digest(normalize_user_code(code)))
    end

    raise ActiveRecord::RecordNotUnique, "Could not generate a unique CLI device user code"
  end

  def generated_user_code
    chars = Array.new(8) { CliDeviceAuthorization::USER_CODE_ALPHABET.sample }.join
    "#{chars.first(4)}-#{chars.last(4)}"
  end
end
