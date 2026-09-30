# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController do
  describe "safe_cache_fetch" do
    let(:controller) { described_class.new }

    it "does not rerun a failing database computation" do
      allow(Rails.cache).to receive(:fetch).and_yield
      calls = 0

      expect do
        controller.send(:safe_cache_fetch, "test", expires_in: 1.minute) do
          calls += 1
          raise ActiveRecord::QueryCanceled, "statement timeout"
        end
      end.to raise_error(ActiveRecord::QueryCanceled)
      expect(calls).to eq(1)
    end

    it "keeps a successful result when the cache write fails" do
      allow(Rails.cache).to receive(:fetch) do |*_args, **_options, &block|
        block.call
        raise "cache write failed"
      end
      calls = 0

      expect(controller.send(:safe_cache_fetch, "test", expires_in: 1.minute) { calls += 1 }).to eq(1)
      expect(calls).to eq(1)
    end

    it "computes once when the cache read fails" do
      allow(Rails.cache).to receive(:fetch).and_raise("cache unavailable")
      calls = 0

      expect(controller.send(:safe_cache_fetch, "test", expires_in: 1.minute) { calls += 1 }).to eq(1)
      expect(calls).to eq(1)
    end
  end
end
