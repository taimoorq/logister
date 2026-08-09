# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectInsightsCache do
  describe "cache failure handling" do
    it "does not retry a failed insights computation" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)
      calls = 0

      expect do
        described_class.send(:fetch, "failing-computation", expires_in: 1.minute) do
          calls += 1
          raise "query failed"
        end
      end.to raise_error(RuntimeError, "query failed")

      expect(calls).to eq(1)
    end

    it "returns an already-computed value when the cache write fails" do
      cache = Class.new do
        def fetch(_key, **)
          yield
          raise "cache write failed"
        end
      end.new
      allow(Rails).to receive(:cache).and_return(cache)
      calls = 0

      value = described_class.send(:fetch, "failed-write", expires_in: 1.minute) do
        calls += 1
        { ok: true }
      end

      expect(value).to eq(ok: true)
      expect(calls).to eq(1)
    end
  end
end
