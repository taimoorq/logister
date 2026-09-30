# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Project inbox page", type: :request do
  describe "GET /projects/:uuid/inbox" do
    context "when signed in as owner" do
      before { sign_in users(:one) }

      it "points activity-only .NET projects from the empty inbox to Events" do
        project = create(:project, :dotnet, user: users(:one), name: "quria-work")
        api_key = create(:api_key, project: project, user: users(:one))
        create(:ingest_event, :transaction, project: project, api_key: api_key)

        get inbox_project_path(project)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        inbox = document.at_css("turbo-frame#project_inbox")

        expect(inbox.text).to include("No errors matching this filter")
        expect(inbox.text).to include("Those live in")
        expect(inbox.at_css("a[href='#{activity_project_path(project)}']").text).to eq("Events")
      end

      it "renders the selected group's latest event in the inbox detail pane" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Inbox")
        api_key = create(:api_key, user: users(:one), project: project, name: "python-inbox")
        latest_event = create(:ingest_event,
                              project: project,
                              api_key: api_key,
                              event_type: :error,
                              message: "Latest grouped error",
                              fingerprint: "python-inbox-error")
        error_group = ErrorGroup.create!(
          project: project,
          latest_event: latest_event,
          fingerprint: "python-inbox-error",
          title: "Latest grouped error",
          status: :unresolved,
          first_seen_at: latest_event.occurred_at,
          last_seen_at: latest_event.occurred_at,
          occurrence_count: 1
        )
        latest_event.update!(error_group: error_group)
        ErrorOccurrence.create!(error_group: error_group, ingest_event: latest_event, occurred_at: latest_event.occurred_at)

        get inbox_project_path(project, group_uuid: error_group.uuid)

        expect(response).to have_http_status(:success)
        detail_frame = Nokogiri::HTML.parse(response.body).at_css('turbo-frame#error_detail')

        expect(detail_frame).to be_present
        expect(detail_frame.text).to include("Latest grouped error")
        expect(detail_frame.text).to include("Related logs")
        expect(detail_frame.text).to include("Export JSON", "Include latest 50 occurrences")
        export_form = detail_frame.at_css("form[action='#{export_project_error_group_path(project, error_group)}'][data-turbo='false']")
        expect(export_form).to be_present
        expect(export_form["data-controller"]).to eq("error-export")
        expect(export_form["data-action"]).to include("submit->error-export#download")
        expect(export_form["data-error-export-filename"]).to eq("logister-error-#{error_group.uuid}.json")
        expect(export_form["target"]).to eq("_top")
        expect(export_form.at_css("input[type='checkbox'][name='include_occurrences'][value='1']")).to be_present
        expect(export_form.at_css("button[data-error-export-target='button']")).to be_present
      end

      it "marks the active filter and selected inbox row with accessible state attributes" do
        get inbox_project_path(projects(:system_inbox), filter: "unresolved", group_uuid: error_groups(:system_primary_group).uuid)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        active_filter = document.at_css(".inbox-filter-link[aria-current='page']")
        selected_row = document.at_css("tr.inbox-row[aria-selected='true']")

        expect(active_filter).to be_present
        expect(active_filter.text).to include("Open")
        expect(selected_row).to be_present
        expect(selected_row["id"]).to eq(ActionView::RecordIdentifier.dom_id(error_groups(:system_primary_group)))
      end

      it "renders the inbox controls as a top filter bar and uses compact row metadata" do
        get inbox_project_path(projects(:system_inbox), filter: "unresolved", group_uuid: error_groups(:system_primary_group).uuid)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        filter_bar = document.at_css(".inbox-workbench > .inbox-workbench-filters .inbox-filter-bar")

        expect(document.at_css("[data-product-tour-group-value='project-errors']")).to be_present
        expect(document.css("[data-tg-group='project-errors']").map { |node| node["data-tg-title"] }).to eq([
          "Inbox filters",
          "Error groups",
          "Error detail"
        ])
        expect(document.css("[data-tg-group='project-errors']").map { |node| node["data-tg-title"] }).not_to include("Error command center", "Project navigation")
        expect(document.at_css(".project-command-panel nav[aria-label='Project sections']")).to be_present
        expect(document.at_css(".project-signals-menu")).to be_nil
        expect(document.at_css(".project-command-actions .projects-secondary-button")).to be_nil
        expect(document.at_css(".projects-overview-strip[aria-label='Project status']")).to be_nil
        expect(filter_bar).to be_present
        expect(document.at_css(".inbox-workbench > .inbox-workbench-sidebar")).to be_nil
        expect(filter_bar.at_css("form.inbox-filter-search input[name='q']")["placeholder"]).to eq("Search errors...")
        expect(filter_bar.css("#inbox_counts .inbox-filter-link").map(&:text).join(" ")).to include("Open", "Introduced today", "Resolved", "Ignored", "Archived", "All")

        table = document.at_css("turbo-frame#project_inbox table.inbox-table-compact[aria-label='Error groups']")
        expect(table).to be_present
        expect(table.at_css("thead")).to be_nil
        expect(table.css("td.col-num, td.col-trend, td.col-stage, td.col-severity")).to be_empty

        row = table.at_css("tr##{ActionView::RecordIdentifier.dom_id(error_groups(:system_primary_group))}")
        expect(row).to be_present

        primary_line = row.at_css(".error-row-primary")
        metadata = row.at_css(".error-meta-row")

        expect(primary_line.at_css(".error-title").text).to eq("Primary inbox error")
        expect(primary_line.at_css(".error-subtitle").text).to eq("RuntimeError")
        expect(metadata.at_css(".error-meta-chip[title='1 event']")).to be_present
        expect(metadata.at_css(".error-meta-trend")["title"]).to include("7 day trend")
        expect(metadata.at_css(".stage-tag-compact")["title"]).to eq("Stage: production")
        expect(metadata.at_css(".severity-compact.severity-error")["title"]).to eq("Severity: error")
        expect(metadata.at_css(".error-meta-time")["title"]).to include("First seen", "Last seen")
        expect(metadata.css(".inbox-info-icon").size).to be >= 3
      end

      it "filters the inbox by assignee while preserving server-rendered controls" do
        project = create(:project, user: users(:one), name: "Assigned Inbox")
        api_key = create(:api_key, project: project, user: users(:one))
        member = create(:user, name: "Project Member")
        create(:project_membership, project: project, user: member)

        mine = create(:error_group, :with_occurrence,
                      project: project,
                      api_key: api_key,
                      title: "Mine assigned error",
                      assignee: users(:one),
                      assigned_by: users(:one),
                      assigned_at: Time.current)
        create(:error_group, :with_occurrence,
               project: project,
               api_key: api_key,
               title: "Member assigned error",
               assignee: member,
               assigned_by: users(:one),
               assigned_at: Time.current)
        create(:error_group, :with_occurrence,
               project: project,
               api_key: api_key,
               title: "Unassigned error")

        get inbox_project_path(project, filter: "unresolved", assignee: "me", group_uuid: mine.uuid)

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        rows_text = document.css("tr.inbox-row").map(&:text).join(" ")
        selected_option = document.at_css("select[name='assignee'] option[selected]")

        expect(rows_text).to include("Mine assigned error")
        expect(rows_text).not_to include("Member assigned error", "Unassigned error")
        expect(rows_text).to include(users(:one).name.presence || users(:one).email)
        expect(selected_option["value"]).to eq("me")
        expect(document.at_css("input[name='assignee'][value='me']")).to be_present
        expect(document.at_css("#inbox_counts .inbox-filter-link[aria-current='page']").text).to include("Open", "1")

        get inbox_project_path(project, filter: "unresolved", assignee: "unassigned")

        document = Nokogiri::HTML.parse(response.body)
        rows_text = document.css("tr.inbox-row").map(&:text).join(" ")

        expect(rows_text).to include("Unassigned error")
        expect(rows_text).not_to include("Mine assigned error", "Member assigned error")

        get inbox_project_path(project, filter: "unresolved", assignee: member.uuid)

        document = Nokogiri::HTML.parse(response.body)
        rows_text = document.css("tr.inbox-row").map(&:text).join(" ")

        expect(rows_text).to include("Member assigned error")
        expect(rows_text).not_to include("Mine assigned error", "Unassigned error")
      end

      it "limits the initial inbox list for high-volume projects" do
        project = create(:project, user: users(:one), name: "Large Inbox")
        ProjectInboxData::INBOX_LIMIT.next.times do |offset|
          create(:error_group,
                 project: project,
                 title: "Large inbox error #{offset}",
                 last_seen_at: offset.minutes.ago,
                 first_seen_at: offset.minutes.ago)
        end

        get inbox_project_path(project, filter: "unresolved")

        expect(response).to have_http_status(:success)

        document = Nokogiri::HTML.parse(response.body)
        expect(document.css("tr.inbox-row").size).to eq(ProjectInboxData::INBOX_LIMIT)
        expect(document.at_css(".inbox-pane-header").text).to include("#{ProjectInboxData::INBOX_LIMIT} shown", "newest first")
      end

      it "ignores a selected event when it does not belong to the selected group" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Inbox")
        api_key = create(:api_key, user: users(:one), project: project, name: "python-inbox")

        selected_group_event = create(:ingest_event,
                                      project: project,
                                      api_key: api_key,
                                      event_type: :error,
                                      message: "Grouped event detail",
                                      fingerprint: "selected-group-error")
        selected_group = ErrorGroup.create!(
          project: project,
          latest_event: selected_group_event,
          fingerprint: "selected-group-error",
          title: "Grouped event detail",
          status: :unresolved,
          first_seen_at: selected_group_event.occurred_at,
          last_seen_at: selected_group_event.occurred_at,
          occurrence_count: 1
        )
        selected_group_event.update!(error_group: selected_group)
        ErrorOccurrence.create!(error_group: selected_group, ingest_event: selected_group_event, occurred_at: selected_group_event.occurred_at)

        mismatched_event = create(:ingest_event,
                                  project: project,
                                  api_key: api_key,
                                  event_type: :error,
                                  message: "Wrong event detail",
                                  fingerprint: "other-group-error")
        other_group = ErrorGroup.create!(
          project: project,
          latest_event: mismatched_event,
          fingerprint: "other-group-error",
          title: "Wrong event detail",
          status: :unresolved,
          first_seen_at: mismatched_event.occurred_at,
          last_seen_at: mismatched_event.occurred_at,
          occurrence_count: 1
        )
        mismatched_event.update!(error_group: other_group)
        ErrorOccurrence.create!(error_group: other_group, ingest_event: mismatched_event, occurred_at: mismatched_event.occurred_at)

        get inbox_project_path(project, group_uuid: selected_group.uuid, event_uuid: mismatched_event.uuid)

        expect(response).to have_http_status(:success)
        detail_frame = Nokogiri::HTML.parse(response.body).at_css('turbo-frame#error_detail')

        expect(detail_frame).to be_present
        expect(detail_frame.text).to include("Grouped event detail")
        expect(detail_frame.text).not_to include("Wrong event detail")
      end
    end
  end
end
