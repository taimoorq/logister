# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project inbox", type: :system do
  include ActionView::RecordIdentifier

  def sign_in_user
    sign_in users(:one)
  end

  def dismiss_product_tour
    find("#tg-dialog-close-btn").click if page.has_css?("#tg-dialog-close-btn", wait: 1)
  end

  it "updates the detail pane through Turbo when opening a different inbox row" do
    sign_in_user

    visit inbox_project_path(projects(:system_inbox))
    dismiss_product_tour
    expect(page).to have_current_path(inbox_project_path(projects(:system_inbox)))
    expect(page).to have_css("turbo-frame#error_detail")

    within("turbo-frame#error_detail") do
      expect(page).to have_content("Primary inbox error")
    end

    click_link "Secondary inbox error"

    within("turbo-frame#error_detail") do
      expect(page).to have_content("Secondary inbox error")
      expect(page).to have_content("OrdersController#create")
    end

    expect(page).to have_css("tr##{dom_id(error_groups(:system_secondary_group))}[aria-selected='true']")
    expect(page).to have_css("tr##{dom_id(error_groups(:system_primary_group))}[aria-selected='false']")
  end

  it "renders the inbox filters and error rows in the compact layout" do
    sign_in_user

    visit inbox_project_path(projects(:system_inbox), group_uuid: error_groups(:system_primary_group).uuid)
    dismiss_product_tour

    expect(page).to have_css(".inbox-workbench > .inbox-workbench-filters .inbox-filter-bar")
    expect(page).to have_no_css(".inbox-workbench-sidebar")

    within(".inbox-filter-bar") do
      expect(page).to have_field("Search inbox")
      expect(page).to have_link("Open")
      expect(page).to have_link("Introduced today")
      expect(page).to have_link("Resolved")
      expect(page).to have_link("Ignored")
      expect(page).to have_link("Archived")
      expect(page).to have_link("All")
    end

    within("turbo-frame#project_inbox") do
      expect(page).to have_css("table.inbox-table-compact[aria-label='Error groups']")
      expect(page).to have_no_css("thead")

      within("tr##{dom_id(error_groups(:system_primary_group))}") do
        expect(page).to have_css(".error-row-primary .error-title", text: "Primary inbox error")
        expect(page).to have_css(".error-row-primary .error-subtitle", text: "RuntimeError")
        expect(page).to have_css(".error-meta-row .error-meta-chip[title='1 event']")
        expect(page).to have_css(".error-meta-row .error-meta-trend[title*='7 day trend']")
        expect(page).to have_css(".stage-tag-compact[title='Stage: production']", text: "production")
        expect(page).to have_css(".severity-compact.severity-error[title='Severity: error']", text: "error")
        expect(page).to have_css(".error-meta-time[title*='First seen']")
        expect(page).to have_css(".inbox-info-icon", minimum: 3)
      end
    end
  end

  it "switches detail tabs within the Turbo frame" do
    sign_in_user

    visit inbox_project_path(projects(:system_inbox), group_uuid: error_groups(:system_primary_group).uuid)
    dismiss_product_tour
    expect(page).to have_current_path(inbox_project_path(projects(:system_inbox), group_uuid: error_groups(:system_primary_group).uuid))
    expect(page).to have_css("turbo-frame#error_detail")

    within("turbo-frame#error_detail") do
      expect(page).to have_content("Primary inbox error")
      click_link "Related logs (1)"
    end

    expect(page).to have_css(
      "turbo-frame#error_detail #tab-related-logs:not([hidden])",
      text: "Related log for the primary inbox error"
    )

    within("turbo-frame#error_detail") do
      expect(page).to have_css(".detail-tab[aria-current='page']", text: "Related logs (1)")
    end
  end

  it "keeps Android profile filters in out-of-frame controls and status links" do
    sign_in_user
    payload = JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read)
    project = create(:project, :android, user: users(:one), name: "System Android")
    api_key = create(:api_key, project: project, user: users(:one))
    event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      event_type: :error,
      level: payload.fetch("level"),
      message: payload.fetch("message"),
      context: payload.fetch("context")
    )
    ErrorGroupingService.call(event)

    visit inbox_project_path(project)
    dismiss_product_tour
    select "1.4.0+42", from: "Release"

    expect(page).to have_select("Release", selected: "1.4.0+42")
    expect(page).to have_css("turbo-frame#project_inbox [data-inbox-state-url*='release=1.4.0']", visible: :all)
    state_url = find("turbo-frame#project_inbox [data-inbox-state-url]", visible: :all)["data-inbox-state-url"]
    state = URI.decode_www_form(URI.parse(state_url).query).to_h
    expect(state["release"]).to eq("1.4.0+42")
    within("#inbox_counts") do
      expect(find_link("All", exact_text: true)[:href]).to include("release=1.4.0%2B42")
    end
    expect(find_link("Clear mobile filters", visible: :all)[:href]).not_to include("release=")
  end

  it "renders the JSON export form as a top-level non-Turbo download request" do
    sign_in_user

    visit inbox_project_path(projects(:system_inbox), group_uuid: error_groups(:system_primary_group).uuid)
    dismiss_product_tour

    within("turbo-frame#error_detail") do
      form = find("form.detail-export-form", visible: :all)

      expect(form["method"]).to eq("get")
      expect(form["target"]).to eq("_top")
      expect(form["data-turbo"]).to eq("false")
      expect(form["data-controller"]).to eq("error-export")
      expect(form["data-action"]).to include("submit->error-export#download")
      expect(form["action"]).to include(export_project_error_group_path(projects(:system_inbox), error_groups(:system_primary_group)))
      expect(page).to have_field("include_occurrences", type: "checkbox", visible: :all)
      expect(page).to have_css("span", text: "Include latest 50 occurrences", visible: :all)
    end
  end

  it "downloads the JSON export through Stimulus without navigating the Turbo frame" do
    sign_in_user

    project = projects(:system_inbox)
    group = error_groups(:system_primary_group)
    visit inbox_project_path(project, group_uuid: group.uuid)
    dismiss_product_tour
    original_url = page.current_url

    Capybara.using_wait_time(10) do
      page.document.synchronize do
        ready = page.evaluate_script(<<~JS)
          (() => {
            const form = document.querySelector("turbo-frame#error_detail form.detail-export-form");
            return Boolean(
              window.Stimulus &&
              form &&
              window.Stimulus.getControllerForElementAndIdentifier(form, "error-export")
            );
          })()
        JS
        raise Capybara::ExpectationNotMet, "expected error export controller to connect" unless ready
      end
    end

    page.execute_script(<<~JS)
      window.__logisterExportDownload = {};
      window.fetch = async (url, options) => {
        window.__logisterExportDownload.url = url.toString();
        window.__logisterExportDownload.accept = options.headers.Accept;
        return new Response(JSON.stringify({ export: true }), {
          status: 200,
          headers: {
            "Content-Type": "application/json",
            "Content-Disposition": "attachment; filename=\\"spec-export.json\\""
          }
        });
      };

      const form = document.querySelector("turbo-frame#error_detail form.detail-export-form");
      const controller = window.Stimulus.getControllerForElementAndIdentifier(form, "error-export");
      controller.saveBlob = function(blob, filename) {
        window.__logisterExportDownload.filename = filename;
        window.__logisterExportDownload.contentType = blob.type;
      };
    JS

    within("turbo-frame#error_detail") do
      find("summary", text: "Export", exact_text: true).click
      click_button "Export JSON"
    end

    download = nil
    Capybara.using_wait_time(10) do
      page.document.synchronize do
        download = page.evaluate_script("window.__logisterExportDownload")
        raise Capybara::ExpectationNotMet, "expected JSON export download to finish" unless download["filename"].present?
      end
    end

    expect(page.current_url).to eq(original_url)
    expect(page).to have_css("turbo-frame#error_detail", text: "Primary inbox error")
    expect(download["url"]).to include(export_project_error_group_path(project, group))
    expect(download["accept"]).to eq("application/json")
    expect(download["filename"]).to eq("spec-export.json")
    expect(download["contentType"]).to eq("application/json")
  end

  it "keeps the error workspace mounted while selecting Ruby stack frames" do
    sign_in_user

    event = ingest_events(:system_primary_error)
    backtrace = 18.times.map do |index|
      "app/services/orders/worker_#{index}.rb:#{index + 10}:in `step_#{index}`"
    end
    event.update!(context: event.context.deep_merge("exception" => {
      "class" => "RuntimeError",
      "message" => event.message,
      "backtrace" => backtrace
    }))

    visit inbox_project_path(projects(:system_inbox), group_uuid: error_groups(:system_primary_group).uuid)
    dismiss_product_tour

    expect(page).to have_css("turbo-frame#error_detail turbo-frame#stack_frame_source")
    expect(page).to have_css(".frame-list .frame-link", minimum: 18)

    target = find(".frame-link", text: "step_12")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", target)
    page.execute_script(<<~JS)
      window.__logisterStableDetail = document.querySelector("turbo-frame#error_detail");
      window.__logisterStablePageY = window.scrollY;
      window.__logisterStableFrameListY = document.querySelector(".frame-list").scrollTop;
    JS
    page.execute_script("arguments[0].click()", target)

    expect(page).to have_css("turbo-frame#stack_frame_source", text: "worker_12.rb")
    expect(page).to have_css(".frame-item.is-active .frame-link[aria-current='true']", text: "step_12")
    expect(page.evaluate_script("document.querySelector('turbo-frame#error_detail') === window.__logisterStableDetail")).to be(true)
    expect(page.evaluate_script("Math.abs(window.scrollY - window.__logisterStablePageY)")).to be <= 2
    expect(page.evaluate_script("Math.abs(document.querySelector('.frame-list').scrollTop - window.__logisterStableFrameListY)")).to be <= 2
  end
end
