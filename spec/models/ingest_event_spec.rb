# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngestEvent, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:api_key) }
    it { is_expected.to belong_to(:error_group).optional }
    it { is_expected.to have_one(:error_occurrence).dependent(:destroy) }
  end

  describe "enums" do
    it "defines event_type error and metric" do
      expect(ingest_events(:one)).to be_error
      expect(ingest_events(:two)).to be_metric
    end
  end

  describe "validations" do
    it "validates presence of message and occurred_at" do
      event = IngestEvent.new(project: projects(:one), api_key: api_keys(:one), event_type: :error)
      expect(event).not_to be_valid
      expect(event.errors[:message]).to be_present
      expect(event.errors[:occurred_at]).to be_present
    end
  end

  describe "callbacks" do
    it "assigns uuid before validation" do
      event = IngestEvent.new(
        project: projects(:one),
        api_key: api_keys(:one),
        event_type: :error,
        message: "Test",
        occurred_at: Time.current
      )
      event.valid?
      expect(event.uuid).to be_present
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      expect(ingest_events(:one).to_param).to eq(ingest_events(:one).uuid)
    end
  end
end
