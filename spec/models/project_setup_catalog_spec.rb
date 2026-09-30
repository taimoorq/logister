# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSetupCatalog do
  it "validates and covers every project experience" do
    expect(described_class.validate!).to be(true)
    expect(described_class::STEP_KEYS_BY_EXPERIENCE.keys).to match_array(ProjectExperienceDefinition.keys)
  end

  it "uses the same four outcome groups, in the same order, for every experience" do
    expect(described_class::GROUPS.map(&:key)).to eq(%i[receive_data actionable team extend])

    ProjectExperienceDefinition.keys.each do |experience_key|
      groups = described_class.steps_for(experience_key).map(&:group_key).uniq
      expect(groups).to eq(described_class::GROUPS.map(&:key)), "#{experience_key} skips or reorders a group"
    end
  end

  it "makes only the first group required, so finishing it is what makes a project live" do
    expect(described_class::GROUPS.map(&:requirement)).to eq(%i[required recommended recommended optional])
  end

  it "gives each project type its own steps inside the shared groups" do
    steps = ->(experience) { described_class.steps_for(experience).map(&:key) }

    expect(steps.call(:server)).to include(:api_key, :first_event, :performance, :deployments)
    expect(steps.call(:android)).to include(:mobile_token, :first_diagnostic, :release, :mapping, :google_play)
    expect(steps.call(:android)).not_to include(:api_key, :symbols, :app_store)
    expect(steps.call(:ios)).to include(:mobile_token, :first_diagnostic, :app_build, :symbols, :metrickit, :app_store)
    expect(steps.call(:ios)).not_to include(:api_key, :mapping, :google_play)
  end

  it "places every dependency before the step that needs it" do
    ProjectExperienceDefinition.keys.each do |experience_key|
      keys = described_class.steps_for(experience_key).map(&:key)

      described_class.steps_for(experience_key).each do |step|
        step.depends_on.each do |dependency|
          expect(keys.index(dependency)).to be < keys.index(step.key), "#{step.key} must follow #{dependency} for #{experience_key}"
        end
      end
    end
  end

  it "only sequences steps inside the required group, so nothing later is blocked without cause" do
    described_class::STEPS.select { |step| step.depends_on.any? }.each do |step|
      expect(step.group.required?).to be(true), "#{step.key} is blocked on another step outside the required group"
    end
  end

  describe ".skippable?" do
    it "never allows required steps to be skipped" do
      described_class::STEPS.select { |step| step.group.required? }.each do |step|
        expect(described_class.skippable?(step.key)).to be(false), "#{step.key} is required"
      end
    end

    it "never allows the personal alerts step to be skipped for the project" do
      expect(described_class.step(:alerts).personal).to be(true)
      expect(described_class.skippable?(:alerts)).to be(false)
    end

    it "allows recommended and optional project steps to be skipped" do
      expect(described_class.skippable?(:source_repo)).to be(true)
      expect(described_class.skippable?(:linked_projects)).to be(true)
      expect(described_class.skippable?(:teammates)).to be(true)
    end

    it "does not skip an unknown step" do
      expect(described_class.skippable?(:not_a_step)).to be(false)
      expect(described_class.step(nil)).to be_nil
    end
  end

  it "has evidence for every step, so no step can never resolve" do
    ProjectExperienceDefinition.keys.each do |experience_key|
      project_kind = ProjectIntegrationDefinition.all.find { |definition| definition.default_experience_key == experience_key }.key
      project = create(:project, integration_kind: project_kind)
      wanted = described_class.evidence_keys_for(experience_key) - [ :alerts ]

      expect(ProjectSetupStatus.new(project).call.keys).to match_array(wanted)
    end
  end

  it "gives every step a chip label" do
    expect(described_class::STEPS.map(&:chip_label)).to all(be_present)
    expect(described_class.step(:first_event).chip_label).to eq("Waiting for first event")
    expect(described_class.step(:first_diagnostic).chip_label).to eq("Waiting for first diagnostic")
  end
end
