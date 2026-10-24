# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::SetupState do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }

  it "round-trips the user and project for the same user" do
    state = described_class.generate(user: user, project: project)

    expect(described_class.verify(state, user: user)).to have_attributes(user_id: user.id, project_uuid: project.uuid)
  end

  it "generates a distinct token for every install link" do
    expect(described_class.generate(user: user)).not_to eq(described_class.generate(user: user))
  end

  it "allows a state without a project" do
    expect(described_class.verify(described_class.generate(user: user), user: user).project_uuid).to be_nil
  end

  it "rejects another user's state" do
    state = described_class.generate(user: user, project: project)

    expect(described_class.verify(state, user: create(:user))).to be_nil
  end

  it "rejects expired, tampered, foreign-purpose, and blank states" do
    state = described_class.generate(user: user)
    foreign = Rails.application.message_verifier(described_class::PURPOSE).generate({ "user_id" => user.id }, purpose: "other")

    travel(described_class::EXPIRES_IN + 1.second) { expect(described_class.verify(state, user: user)).to be_nil }
    expect(described_class.verify("#{state}x", user: user)).to be_nil
    expect(described_class.verify(project.uuid, user: user)).to be_nil
    expect(described_class.verify(foreign, user: user)).to be_nil
    expect(described_class.verify("", user: user)).to be_nil
    expect(described_class.verify(state, user: nil)).to be_nil
  end
end
