# frozen_string_literal: true

FactoryBot.define do
  factory :cli_device_authorization do
    transient do
      device_code { SecureRandom.urlsafe_base64(48) }
      sequence(:user_code) { |n| "TEST-#{n.to_s(36).upcase.rjust(4, '0').last(4)}" }
    end

    device_code_digest { CliDeviceAuthorization.digest(device_code) }
    user_code_digest { CliDeviceAuthorization.digest(CliDeviceAuthorization.normalize_user_code(user_code)) }
    user_code_display { user_code }
    client_name { "Logister CLI" }
    requested_scopes { CliAccessToken::READ_SCOPES }
    expires_at { 10.minutes.from_now }

    trait :approved do
      association :user
      status { :approved }
      approved_at { Time.current }
      approved_all_projects { true }
    end

    trait :denied do
      status { :denied }
      denied_at { Time.current }
    end

    trait :expired do
      expires_at { 1.minute.ago }
    end
  end
end
