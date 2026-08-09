# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::CliPostgresStatementTimeout do
  it "pins one connection and restores its prior session timeout after the response is built" do
    connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
    connection_pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool)
    allow(connection_pool).to receive(:with_connection).and_yield(connection)
    allow(connection).to receive(:select_value).with("SHOW statement_timeout").and_return("30s")
    allow(connection).to receive(:quote) { |value| "'#{value}'" }

    expect(connection).to receive(:execute).with("SET statement_timeout = '2500ms'").ordered
    expect(connection).to receive(:execute).with("SET statement_timeout = '30s'").ordered

    result = described_class.new(connection_pool:, timeout_ms: 2_500).call { :rendered }

    expect(result).to eq(:rendered)
  end

  it "restores the prior timeout while preserving an action error" do
    connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
    connection_pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool)
    allow(connection_pool).to receive(:with_connection).and_yield(connection)
    allow(connection).to receive(:select_value).with("SHOW statement_timeout").and_return("0")
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
    error = ActiveRecord::QueryCanceled.new("private SQL detail")
    expect(connection).to receive(:execute).with("SET statement_timeout = '500ms'").ordered
    expect(connection).to receive(:execute).with("SET statement_timeout = '0'").ordered

    expect do
      described_class.new(connection_pool:, timeout_ms: 500).call { raise error }
    end.to raise_error(error)
  end

  it "uses a safe default for an invalid configured timeout" do
    allow(ENV).to receive(:fetch).with(described_class::ENV_KEY, described_class::DEFAULT_TIMEOUT_MS.to_s).and_return("invalid")

    expect(described_class.configured_timeout_ms).to eq(described_class::DEFAULT_TIMEOUT_MS)
  end
end
