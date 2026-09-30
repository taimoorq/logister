# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSetupActions do
  def action_keys_for(project)
    keys = ProjectSetupCatalog.steps_for(project.integration_definition.default_experience_key).map(&:action_key)
    ProjectSetupStatus.new(project).call.each_value { |status| keys << status.action_key }
    ProjectCapabilitySnapshot.for(project).statuses.each_value { |status| keys << status.action_key }
    keys.compact.uniq
  end

  it "registers every action a step or evidence loader can emit, so no step lacks somewhere to go" do
    Project.integration_kinds.each_key do |kind|
      project = create(:project, integration_kind: kind)

      unregistered = action_keys_for(project).reject { |key| described_class.registered?(key) }
      expect(unregistered).to be_empty, "#{kind} emits unregistered actions: #{unregistered.join(', ')}"
    end
  end

  it "registers the store import actions for every provider state" do
    { android: "google_play", ios: "app_store_connect" }.each do |kind, provider|
      project = create(:project, kind)
      setting = create(
        :project_integration_setting,
        project: project,
        provider: provider,
        enabled: true,
        external_project_id: "com.acme.shop",
        credential_reference: "STORE_CREDENTIALS"
      )
      emitted = []
      collect = -> { emitted.concat(ProjectSetupStatus.new(project).call.values.map(&:action_key)) }

      collect.call
      setting.update!(last_imported_at: 2.days.ago)
      collect.call
      setting.update!(metadata: { "last_error" => { "message" => "denied", "at" => Time.current.utc.iso8601 } })
      collect.call

      expect(emitted.compact.uniq).to include(:import_distribution_store, :repair_distribution_store)
      expect(emitted.compact.uniq.reject { |key| described_class.registered?(key) }).to be_empty
    end
  end

  it "gives every registered action a label and a kind" do
    described_class.registered_keys.each do |key|
      action = described_class.action_for(key)

      expect(action.label).to be_present
      expect(action.kind).to be_in(%i[form guide])
    end
  end

  it "separates work done in Logister from work done in the project's own code" do
    expect(described_class.action_for(:create_api_key).kind).to eq(:form)
    expect(described_class.action_for(:connect_source_repository).kind).to eq(:form)
    expect(described_class.action_for(:send_first_event).kind).to eq(:guide)
    expect(described_class.action_for(:record_deployment).kind).to eq(:guide)
  end
end
