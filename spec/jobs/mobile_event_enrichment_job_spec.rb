# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobileEventEnrichmentJob, type: :job do
  it "derives Android mapping evidence by project-scoped event identity" do
    project = create(:project, :android)
    event = create(
      :ingest_event,
      project: project,
      context: {
        "platform" => "android",
        "app" => { "package_name" => "com.acme.shop", "version_code" => "42" },
        "exception" => { "stacktrace" => [ { "class_name" => "a", "method_name" => "b", "line_number" => 1 } ] }
      }
    )
    create(:android_mapping_file, project: project, version_code: "42")

    expect do
      described_class.perform_now(project.id, event.uuid, event.occurred_at.utc.iso8601(6))
    end.to change(project.mobile_event_enrichments, :count).by(1)

    expect(project.mobile_event_enrichments.sole).to have_attributes(event_uuid: event.uuid, kind: "android_mapping")
  end

  it "routes iOS evidence to the Apple enrichment service" do
    project = create(:project, :ios)
    event = create(:ingest_event, project:)
    allow(MobileEventEnrichments::Apple).to receive(:call)

    described_class.perform_now(project.id, event.uuid, event.occurred_at.utc.iso8601(6))

    expect(MobileEventEnrichments::Apple).to have_received(:call).with(project:, event:)
  end
end
