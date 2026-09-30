# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/seeds.rb" do
  def run_seeds
    silence_output { load Rails.root.join("db/seeds.rb") }
  end

  def silence_output
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  before { allow(Rails.env).to receive(:development?).and_return(true) }

  it "can be run again later without moving the events other records point at" do
    run_seeds
    events = IngestEvent.where(project: Project.where(name: "Storefront App")).order(:id).pluck(:id, :occurred_at)
    expect(ErrorGroup.where.not(latest_event_id: nil)).to exist

    travel_to(3.hours.from_now) { expect { run_seeds }.not_to raise_error }

    expect(IngestEvent.where(project: Project.where(name: "Storefront App")).order(:id).pluck(:id, :occurred_at)).to eq(events)
  end

  it "adds a notification preference for each seeded person only once" do
    run_seeds
    expect { run_seeds }.not_to change(ProjectNotificationPreference, :count)
  end
end
