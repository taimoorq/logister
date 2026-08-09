# frozen_string_literal: true

FactoryBot.define do
  factory :mobile_event_enrichment do
    project { association :project, :android }
    event_uuid { SecureRandom.uuid }
    event_occurred_at { Time.current }
    platform { "android" }
    kind { "android_mapping" }
    status { "complete" }
    input_sha256 { Digest::SHA256.hexdigest("input") }
    tool_name { "logister_android_mapper" }
    tool_version { "1" }
    data { { "schema_version" => 1, "frames" => [] } }
    processed_at { Time.current }

    trait :apple_symbolication do
      project { association :project, :ios }
      platform { "ios" }
      kind { "apple_symbolication" }
      tool_name { "apple_atos" }
      tool_version { "adapter-1; Xcode test" }
    end
  end
end
