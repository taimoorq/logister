# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub setup callback", type: :request do
  let(:installation_id) { 123 }
  let(:installation_payload) do
    {
      "id" => installation_id,
      "account" => { "login" => "acme", "type" => "Organization" },
      "repository_selection" => "selected",
      "permissions" => { "contents" => "read", "metadata" => "read" },
      "events" => %w[installation installation_repositories]
    }
  end
  let(:repository_payloads) do
    [
      { "id" => 456, "full_name" => "acme/storefront", "default_branch" => "main", "html_url" => "https://github.com/acme/storefront" },
      { "id" => 789, "full_name" => "acme/checkout", "default_branch" => "main", "html_url" => "https://github.com/acme/checkout" }
    ]
  end
  let(:app_client) { instance_double(Github::AppClient, installation: installation_payload) }
  let(:repositories_client) { instance_double(Github::InstallationRepositoriesClient, list: repository_payloads) }

  before do
    allow(Github::AppClient).to receive(:new).and_return(app_client)
    allow(Github::InstallationRepositoriesClient).to receive(:new).and_return(repositories_client)
  end

  def setup_state_for(user, project: nil)
    Github::SetupState.generate(user: user, project: project)
  end

  def expect_refused_setup
    expect(response).to redirect_to(projects_path)
    expect(flash[:alert]).to include("GitHub App setup could not be verified")
  end

  describe "GET /github/setup" do
    it "syncs a new installation, links the project from signed state, and returns to project source settings" do
      project = create(:project, user: users(:one), slug: "newsfeedreader", name: "News Feed Reader")
      sign_in users(:one)

      expect {
        get github_setup_path, params: { installation_id: installation_id.to_s, state: setup_state_for(users(:one), project: project) }
      }.not_to change(ProjectSourceRepository, :count)

      installation = GithubInstallation.find_by!(installation_id: installation_id)
      expect(installation.installed_by).to eq(users(:one))
      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(flash[:notice]).to include("Synced 2 repositories")
      expect(flash[:notice]).to include("Select repositories below")
      expect(project.github_installations).to include(installation)
      expect(project.source_repositories).to be_empty
    end

    it "links the installation when the signed state names a project the user administers" do
      project = create(:project, user: users(:one))
      create(:project_membership, project: project, user: users(:two), role: :admin)
      sign_in users(:two)

      get github_setup_path, params: { installation_id: installation_id.to_s, state: setup_state_for(users(:two), project: project) }

      installation = GithubInstallation.find_by!(installation_id: installation_id)
      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(installation.installed_by).to eq(users(:two))
      expect(project.github_installations).to include(installation)
    end

    it "does not link a project the state user cannot manage" do
      project = create(:project, user: users(:one))
      sign_in users(:two)

      get github_setup_path, params: { installation_id: installation_id.to_s, state: setup_state_for(users(:two), project: project) }

      expect(response).to redirect_to(projects_path)
      expect(project.github_installations).to be_empty
    end

    it "lets the owner resync their installation without a state" do
      installation = create(:github_installation, installation_id: installation_id, installed_by: users(:one))
      sign_in users(:one)

      get github_setup_path, params: { installation_id: installation_id.to_s, setup_action: "update" }

      expect(response).to redirect_to(projects_path)
      expect(flash[:notice]).to include("Synced 2 repositories")
      expect(installation.reload.installed_by).to eq(users(:one))
    end

    it "refuses a new installation without a signed state" do
      sign_in users(:one)

      get github_setup_path, params: { installation_id: installation_id.to_s }

      expect_refused_setup
      expect(GithubInstallation.find_by(installation_id: installation_id)).to be_nil
      expect(app_client).not_to have_received(:installation)
    end

    context "when another user owns the installation" do
      let!(:project) { create(:project, user: users(:two)) }
      let!(:installation) { create(:github_installation, installation_id: installation_id, installed_by: users(:one)) }

      before { sign_in users(:two) }

      {
        "no state" => proc { nil },
        "a bare project uuid state" => proc { project.uuid },
        "a forged state" => proc {
          ActiveSupport::MessageVerifier.new("not-the-app-secret").generate(
            { "user_id" => users(:two).id, "project_uuid" => project.uuid },
            purpose: Github::SetupState::PURPOSE
          )
        },
        "another user's state" => proc { setup_state_for(users(:one), project: project) },
        "the user's own valid state" => proc { setup_state_for(users(:two), project: project) }
      }.each do |description, state_builder|
        it "refuses the claim with #{description}" do
          state = instance_exec(&state_builder)

          expect {
            get github_setup_path, params: { installation_id: installation_id.to_s, state: state }.compact
          }.not_to change(ProjectGithubInstallation, :count)

          expect_refused_setup
          expect(installation.reload.installed_by).to eq(users(:one))
          expect(project.github_installations).to be_empty
          expect(GithubInstallation.visible_to(users(:two))).to be_empty
        end
      end

      it "refuses the claim with an expired state" do
        state = setup_state_for(users(:two), project: project)

        travel Github::SetupState::EXPIRES_IN + 1.minute do
          get github_setup_path, params: { installation_id: installation_id.to_s, state: state }
        end

        expect_refused_setup
        expect(installation.reload.installed_by).to eq(users(:one))
        expect(project.github_installations).to be_empty
      end
    end

    context "when a webhook created the installation without an owner" do
      let!(:installation) { create(:github_installation, installation_id: installation_id, installed_by: nil) }
      let!(:project) { create(:project, user: users(:two)) }

      before { sign_in users(:two) }

      it "refuses the claim without a state" do
        get github_setup_path, params: { installation_id: installation_id.to_s }

        expect_refused_setup
        expect(installation.reload.installed_by).to be_nil
      end

      it "refuses the claim with another user's state" do
        get github_setup_path, params: { installation_id: installation_id.to_s, state: setup_state_for(users(:one), project: project) }

        expect_refused_setup
        expect(installation.reload.installed_by).to be_nil
        expect(project.github_installations).to be_empty
      end

      it "refuses the claim with an expired state" do
        state = setup_state_for(users(:two), project: project)

        travel Github::SetupState::EXPIRES_IN + 1.minute do
          get github_setup_path, params: { installation_id: installation_id.to_s, state: state }
        end

        expect_refused_setup
        expect(installation.reload.installed_by).to be_nil
      end

      it "lets the user claim it with their own valid state" do
        get github_setup_path, params: { installation_id: installation_id.to_s, state: setup_state_for(users(:two), project: project) }

        expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
        expect(installation.reload.installed_by).to eq(users(:two))
        expect(project.github_installations).to include(installation)
      end
    end

    it "requires an authenticated user" do
      get github_setup_path, params: { installation_id: "123" }

      expect(response).to redirect_to(new_user_session_path)
    end

    it "rejects callbacks without an installation id" do
      sign_in users(:one)

      get github_setup_path

      expect(response).to redirect_to(projects_path)
      expect(flash[:alert]).to eq("Missing GitHub installation id.")
    end
  end
end
