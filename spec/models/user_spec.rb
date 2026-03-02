# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it "has many projects" do
      association = described_class.reflect_on_association(:projects)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many shared_projects through project_memberships" do
      expect(users(:one).accessible_projects).to be_a(ActiveRecord::Relation)
    end
  end

  describe "validations" do
    it "validates name length at most 100" do
      user = User.new(email: "a@b.co", password: "password123", name: "a" * 101)
      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end

    it "allows blank name" do
      user = User.new(email: "a@b.co", password: "password123", name: "")
      user.valid?
      expect(user.errors[:name]).to be_blank
    end

    it "validates presence and uniqueness of uuid" do
      user = users(:one)
      expect(user.uuid).to be_present
      dup = User.new(email: "other@example.com", password: "password123", uuid: user.uuid)
      expect(dup).not_to be_valid
      expect(dup.errors[:uuid]).to include("has already been taken")
    end
  end

  describe "callbacks" do
    it "assigns uuid before validation when missing" do
      user = User.new(email: "new@example.com", password: "password123")
      user.valid?
      expect(user.uuid).to be_present
      expect(user.uuid).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "strips and blanks name" do
      user = User.new(email: "n@ex.com", password: "p", name: "  ")
      user.valid?
      expect(user.name).to be_blank
    end
  end

  describe "factory" do
    it "builds a valid user" do
      user = build(:user, name: "Jane")
      expect(user).to be_valid
      expect(user.name).to eq("Jane")
    end

    it "creates a confirmed user" do
      user = create(:user)
      expect(user).to be_persisted
      expect(user).to be_confirmed
      expect(user.email).to match(/@example\.com\z/)
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      user = users(:one)
      expect(user.to_param).to eq(user.uuid)
    end
  end

  describe "#accessible_projects" do
    it "returns projects owned by or shared with the user" do
      user = users(:one)
      expect(user.accessible_projects).to include(projects(:one))
    end

    it "includes shared projects for a member" do
      member = users(:two)
      expect(member.accessible_projects).to include(projects(:one))
    end
  end
end
