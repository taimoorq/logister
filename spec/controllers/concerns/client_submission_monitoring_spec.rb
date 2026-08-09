# frozen_string_literal: true

require "spec_helper"
require "active_support/concern"
require "active_support/core_ext/object/blank"
require_relative "../../../app/controllers/concerns/client_submission_monitoring"

RSpec.describe ClientSubmissionMonitoring do
  let(:harness_class) do
    Class.new do
      include ClientSubmissionMonitoring

      attr_writer :request

      def diagnostic_content_length(summarize_payload:)
        client_submission_content_length(summarize_payload: summarize_payload)
      end

      private

      attr_reader :request
    end
  end

  it "does not read a chunked unauthorized body to calculate diagnostic length" do
    request = double("request", get_header: nil)
    expect(request).not_to receive(:content_length)
    harness = harness_class.new
    harness.request = request

    expect(harness.diagnostic_content_length(summarize_payload: false)).to be_nil
  end

  it "uses declared Content-Length without touching the request body" do
    request = double("request", get_header: "123")
    expect(request).not_to receive(:content_length)
    harness = harness_class.new
    harness.request = request

    expect(harness.diagnostic_content_length(summarize_payload: false)).to eq(123)
  end
end
