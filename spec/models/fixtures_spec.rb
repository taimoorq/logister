# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Application fixture data", type: :model do
  it "satisfies model validations even though fixture inserts bypass them" do
    records = self.class.fixture_table_names.flat_map { |table| public_send(table) }

    expect(records).not_to be_empty
    expect(records).to all(be_valid)
  end

  it "keeps the inbox groups linked to their events by the complete partition reference" do
    %i[primary secondary].each do |name|
      group = error_groups("system_#{name}_group")
      event = ingest_events("system_#{name}_error")

      expect(group.latest_event_occurred_at).to eq(event.occurred_at)
      expect(group.latest_event_record).to eq(event)
      expect(group.error_occurrences.sole.ingest_event).to eq(event)
      expect(event.error_group).to eq(group)
      expect(event.project).to eq(group.project)
    end
  end

  it "still rejects an orphan inserted while fixture foreign-key triggers are disabled" do
    connection = ApplicationRecord.connection

    expect do
      connection.transaction(requires_new: true) do
        connection.disable_referential_integrity do
          ApiKey.where(id: api_keys(:one).id).update_all(project_id: -1)
        end
        connection.check_all_foreign_keys_valid!
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "rejects a partition reference whose timestamp does not identify an event" do
    connection = ApplicationRecord.connection
    group = error_groups(:system_primary_group)

    expect do
      connection.transaction(requires_new: true) do
        connection.disable_referential_integrity do
          ErrorGroup.where(id: group.id).update_all(latest_event_occurred_at: group.latest_event_occurred_at + 1.second)
        end
        connection.check_all_foreign_keys_valid!
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
