# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error group external links", type: :request do
  let(:project) { projects(:system_inbox) }
  let(:group) { error_groups(:system_primary_group) }

  before { sign_in users(:one) }

  describe "POST /projects/:project_uuid/error_groups/:error_group_uuid/external_links" do
    it "attaches a GitHub issue link to an accessible error group" do
      post project_error_group_external_links_path(project, group),
           params: {
             error_group_external_link: {
               url: "https://github.com/acme/storefront/issues/42?utm=ignored"
             }
           }

      expect(response).to redirect_to(inbox_project_path(project, filter: "unresolved", q: "", assignee: "all", group_uuid: group.uuid))
      link = group.external_links.last
      expect(link).to have_attributes(
        project: project,
        created_by: users(:one),
        url: "https://github.com/acme/storefront/issues/42",
        link_type: "issue",
        repository_full_name: "acme/storefront",
        external_id: "42"
      )
    end

    it "returns turbo stream detail updates" do
      post project_error_group_external_links_path(project, group),
           params: {
             error_group_external_link: {
               url: "https://github.com/acme/storefront/pull/7"
             }
           },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("error_detail")
      expect(group.external_links.last).to be_link_type_pull_request
    end

    it "does not attach invalid GitHub URLs" do
      expect do
        post project_error_group_external_links_path(project, group),
             params: {
               error_group_external_link: {
                 url: "https://github.com/acme/storefront/actions/runs/42"
               }
             }
      end.not_to change(ErrorGroupExternalLink, :count)

      expect(response).to redirect_to(inbox_project_path(project, filter: "unresolved", q: "", assignee: "all", group_uuid: group.uuid))
      expect(flash[:alert]).to include("must be a GitHub issue or pull request URL")
    end
  end

  describe "POST /projects/:project_uuid/error_groups/:error_group_uuid/github_issue" do
    it "creates a GitHub issue and attaches the returned issue URL" do
      repository = create(:project_source_repository, project: project, full_name: "acme/storefront")
      result = Github::IssueCreator::Result.new(
        html_url: "https://github.com/acme/storefront/issues/42",
        number: 42,
        title: "[System Inbox] Primary Error",
        body: "Issue body",
        repository_full_name: "acme/storefront"
      )
      allow(Github::IssueCreator).to receive(:call).and_return(result)

      expect do
        post project_error_group_github_issue_path(project, group),
             params: { repository_uuid: repository.uuid }
      end.to change(ErrorGroupExternalLink, :count).by(1)

      expect(response).to redirect_to(inbox_project_path(project, filter: "unresolved", q: "", assignee: "all", group_uuid: group.uuid))
      link = group.external_links.last
      expect(link).to have_attributes(
        url: "https://github.com/acme/storefront/issues/42",
        link_type: "issue",
        repository_full_name: "acme/storefront",
        external_id: "42",
        title: "[System Inbox] Primary Error"
      )
      expect(link.metadata).to include("source" => "github_api", "body" => "Issue body")
    end
  end

  describe "DELETE /projects/:project_uuid/error_groups/:error_group_uuid/external_links/:uuid" do
    it "removes a GitHub link" do
      link = create(:error_group_external_link, project: project, error_group: group)

      delete project_error_group_external_link_path(project, group, link)

      expect(response).to redirect_to(inbox_project_path(project, filter: "unresolved", q: "", assignee: "all", group_uuid: group.uuid))
      expect(ErrorGroupExternalLink.exists?(link.id)).to be(false)
    end
  end
end
