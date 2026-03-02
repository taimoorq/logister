# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngestEvent, type: :model do
  describe "associations" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end

    it "belongs to api_key" do
      expect(described_class.reflect_on_association(:api_key).macro).to eq(:belongs_to)
    end

    it "belongs to error_group optional" do
      a = described_class.reflect_on_association(:error_group)
      expect(a.macro).to eq(:belongs_to)
      expect(a.optional?).to be true
    end

    it "has one error_occurrence dependent destroy" do
      a = described_class.reflect_on_association(:error_occurrence)
      expect(a.macro).to eq(:has_one)
      expect(a.options[:dependent]).to eq(:destroy)
    end
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
