# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::CodeownersFile do
  it "uses the last matching entry and strips inline comments" do
    file = described_class.parse(<<~CODEOWNERS)
      # Default owners
      * @global-owner
      *.rb @ruby-owner # inline comment
      app/models/order.rb docs@example.com
    CODEOWNERS

    entry = file.match("app/models/order.rb")

    expect(entry.owners).to eq([ "docs@example.com" ])
    expect(entry.line_number).to eq(4)
  end

  it "matches anchored directories and unanchored directory names" do
    file = described_class.parse(<<~CODEOWNERS)
      /app/controllers/ @controllers
      services/ @services
    CODEOWNERS

    expect(file.owners_for("app/controllers/orders_controller.rb")).to eq([ "@controllers" ])
    expect(file.owners_for("engines/billing/services/checkout.rb")).to eq([ "@services" ])
  end

  it "allows empty-owner entries to clear previous owners" do
    file = described_class.parse(<<~CODEOWNERS)
      /app/ @app-owner
      /app/generated/
    CODEOWNERS

    expect(file.owners_for("app/generated/schema.rb")).to eq([])
  end

  it "skips unsupported CODEOWNERS pattern syntax" do
    file = described_class.parse(<<~CODEOWNERS)
      !ignored.rb @ignored
      [abc].rb @range
      *.rb @ruby
    CODEOWNERS

    expect(file.owners_for("ignored.rb")).to eq([ "@ruby" ])
  end
end
