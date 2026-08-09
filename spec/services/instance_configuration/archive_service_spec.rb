# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration::ArchiveService do
  it "builds the exact recorded local generation and rejects locator tampering" do
    locator = described_class.with_generation_id(
      "service" => "local",
      "root" => Rails.root.join("tmp", "archive-generation-test").to_s
    )

    expect(described_class.build(locator: locator)).to be_a(ActiveStorage::Service::DiskService)

    tampered = locator.merge("root" => Rails.root.join("tmp", "other-store").to_s)
    expect { described_class.build(locator: tampered) }
      .to raise_error(ArgumentError, /generation checksum/)
  end
end
