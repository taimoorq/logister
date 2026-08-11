# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectArchiveObjectCatalog do
  it "pages v2 keys from normalized object rows and ignores legacy parent JSON" do
    archive = create(
      :telemetry_archive,
      manifest_version: 2,
      objects: [ { "key" => "legacy/should-not-render.jsonl.gz" } ]
    )
    25.times do |sequence|
      create(
        :telemetry_archive_object,
        telemetry_archive: archive,
        sequence: sequence,
        object_key: format("telemetry/part-%02d.jsonl.gz", sequence)
      )
    end

    first = described_class.new(archives: [ archive ]).call.fetch(archive.id)
    second = described_class.new(
      archives: [ archive ],
      selected_archive_id: archive.id,
      requested_page: 2
    ).call.fetch(archive.id)

    expect(first).to have_attributes(total: 25, page: 1, total_pages: 2)
    expect(first.object_keys.size).to eq(20)
    expect(first.object_keys).not_to include("legacy/should-not-render.jsonl.gz")
    expect(second.object_keys).to eq((20..24).map { |sequence| format("telemetry/part-%02d.jsonl.gz", sequence) })
  end

  it "keeps legacy parent JSON readable with the same bounded page contract" do
    archive = create(
      :telemetry_archive,
      manifest_version: 1,
      objects: 21.times.map { |number| { "key" => "legacy/part-#{number}.jsonl.gz" } }
    )

    page = described_class.new(
      archives: [ archive ],
      selected_archive_id: archive.id,
      requested_page: 2
    ).call.fetch(archive.id)

    expect(page).to have_attributes(total: 21, page: 2, total_pages: 2)
    expect(page.object_keys).to eq([ "legacy/part-20.jsonl.gz" ])
  end
end
