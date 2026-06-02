# frozen_string_literal: true

require "rails_helper"

RSpec.describe CloudflarePagesImportJob, type: :job do
  it "delegates to the Cloudflare Pages importer" do
    setting = create(:project_integration_setting)

    allow(Logister::CloudflarePagesImporter).to receive(:call)

    described_class.perform_now(setting.id)

    expect(Logister::CloudflarePagesImporter).to have_received(:call).with(setting)
  end
end
