# frozen_string_literal: true

FactoryBot.define do
  factory :android_mapping_file do
    project { association :project, :android }
    uploaded_by { project.user }
    package_name { "com.acme.shop" }
    sequence(:version_code) { |number| (40 + number).to_s }
    version_name { "1.4.0" }
    release { "1.4.0+42" }
    content { "com.acme.RealClass -> a:\n    1:2:void call():10:11 -> b\n" }
    byte_size { content.bytesize }
    checksum_sha256 { Digest::SHA256.hexdigest(content) }
  end
end
