# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::IosEventPresenter do
  subject(:presenter) { described_class.new(event) }

  let(:payload) { JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read) }
  let(:event) { Struct.new(:context, :message).new(payload.fetch("context"), payload.fetch("message")) }

  it "reads Apple symbols and canonical mobile context" do
    expect(presenter.exception_type).to eq("CheckoutError")
    expect(presenter.mechanism_label).to eq("Reported exception")
    expect(presenter.top_in_app_frame).to include(
      image: "AcmeShop",
      method_name: "CheckoutViewModel.submit(_:)",
      application_frame: true
    )
    expect(presenter.app_details).to include(bundle_identifier: "com.acme.shop", version_name: "4.2.0", version_code: "310")
    expect(presenter.device_details).to include(model: "iPhone17,1", family: "iPhone")
    expect(presenter.os_details).to include(name: "iOS", version: "19.0")
  end
end
