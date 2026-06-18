# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Deployments", type: :request do
  describe "POST /api/v1/deployments" do
    let(:project) { api_keys(:one).project }
    let(:auth_headers) { { "Authorization" => "Bearer test-token-one" } }

    before do
      allow(Logister).to receive(:report_log).and_return(true)
      create(:project_source_repository, project: project, full_name: "acme/storefront")
    end

    it "indexes a deployment for the authenticated project" do
      expect {
        post api_v1_deployments_path,
             params: {
               deployment: {
                 release: "2026.06.18",
                 environment: "production",
                 repository: "acme/storefront",
                 commit_sha: "ABC1234",
                 branch: "main",
                 deployed_at: "2026-06-18T15:20:00Z",
                 pull_request_number: 42,
                 release_tag: "v2026.06.18",
                 workflow_run_url: "https://github.com/acme/storefront/actions/runs/123"
               }
             },
             as: :json,
             headers: auth_headers
      }.to change(ProjectDeployment, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["status"]).to eq("accepted")

      deployment = ProjectDeployment.find_by!(uuid: response.parsed_body["id"])
      expect(deployment.project_id).to eq(project.id)
      expect(deployment.repository_full_name).to eq("acme/storefront")
      expect(deployment.commit_sha).to eq("abc1234")
      expect(deployment.deployed_at.iso8601).to eq("2026-06-18T15:20:00Z")
      expect(deployment.metadata).to include(
        "pull_request_number" => "42",
        "pull_request_url" => "https://github.com/acme/storefront/pull/42",
        "release_tag" => "v2026.06.18",
        "workflow_run_url" => "https://github.com/acme/storefront/actions/runs/123"
      )
    end

    it "accepts uppercase deployment envelopes" do
      post api_v1_deployments_path,
           params: {
             DEPLOYMENT: {
               RELEASE: "2026.06.18",
               ENVIRONMENT: "production",
               REPOSITORY: "acme/storefront",
               COMMIT_SHA: "abc1234"
             }
           },
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(:created)
      expect(ProjectDeployment.find_by!(uuid: response.parsed_body["id"]).release).to eq("2026.06.18")
    end

    it "returns 422 for invalid deployment payloads" do
      post api_v1_deployments_path,
           params: {
             deployment: {
               release: "2026.06.18",
               repository: "acme/storefront",
               commit_sha: "not-a-sha"
             }
           },
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body["errors"]).to include("Commit sha must be a 7 to 40 character commit SHA")
      expect(Logister).to have_received(:report_log).with(
        message: "Client deployment rejected",
        level: "warn",
        fingerprint: "client-submission:deployment:invalid_deployment",
        context: hash_including(
          client_submission: hash_including(reason: "invalid_deployment", status: 422)
        )
      )
    end

    it "returns 400 when the deployment envelope is missing" do
      post api_v1_deployments_path,
           params: { payload: { release: "2026.06.18" } },
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("deployment")
      expect(Logister).to have_received(:report_log).with(
        message: "Client deployment rejected",
        level: "warn",
        fingerprint: "client-submission:deployment:missing_deployment_envelope",
        context: hash_including(
          client_submission: hash_including(reason: "missing_deployment_envelope", status: 400)
        )
      )
    end
  end
end
