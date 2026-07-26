# frozen_string_literal: true

FactoryBot.define do
  factory :apple_symbol_artifact do
    project { association :project, :ios }
    uploaded_by { project.user }
    app_identifier { "com.acme.shop" }
    version_name { "4.2.0" }
    sequence(:version_code) { |number| (300 + number).to_s }
    release { "4.2.0+310" }
    sequence(:binary_uuid) { |number| format("AAAAAAAA-BBBB-CCCC-DDDD-%012d", number) }
    architecture { "arm64" }
    sequence(:checksum_sha256) { |number| Digest::SHA256.hexdigest("symbols-#{number}") }
    byte_size { 1_024 }
    filename { "AcmeShop.dSYM.zip" }
    content_type { "application/zip" }
    sequence(:storage_key) { |number| "telemetry/apple-symbols/project=#{project.uuid}/#{number}.zip" }
    status { "uploaded" }
  end
end
