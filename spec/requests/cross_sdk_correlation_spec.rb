require "rails_helper"

RSpec.describe "Mobile to Rails wire correlation", type: :request do
  %w[ios android].each do |platform|
    it "ingests real #{platform} and Rails SDK envelopes into separate projects and finds the backend request" do
      fixture = JSON.parse(Rails.root.join("spec/fixtures/correlation/#{platform}.json").read)
      server = JSON.parse(Rails.root.join("spec/fixtures/correlation/ruby-#{platform}.json").read)
      mobile = create(:project, integration_kind: platform, user: users(:one), cross_project_correlations_enabled: true)
      backend = create(:project, user: users(:one), cross_project_correlations_enabled: true)
      mobile_key = create(:api_key, project: mobile, user: users(:one))
      backend_key = create(:api_key, project: backend, user: users(:one))
      token = MobileIngestToken.create!(project: mobile, api_key: mobile_key, platform:, service: "correlation-test", environment: "production", release: "mobile-test", expires_at: 15.minutes.from_now)
      ProjectLink.connect!(actor: users(:one), source: mobile, target: backend, environment_pairs: [ { "source" => "production", "target" => "test" } ])
      allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)

      [ [ fixture, token.plain_token ], [ server, backend_key.plain_token ] ].each do |data, credential|
        data.fetch("envelopes").each do |envelope|
          post api_v1_ingest_events_path, params: envelope, as: :json, headers: { "Authorization" => "Bearer #{credential}" }
          expect(response).to have_http_status(:created), response.body
        end
      end
      anchor = mobile.ingest_events.where(event_type: "error").first!
      result = ProjectCorrelationsQuery.call(principal: users(:one), project: mobile, event: anchor)
      backend_rows = result[:items].select { |row| row[:project_uuid] == backend.uuid }
      expect(backend_rows.map { |row| row[:type] }).to contain_exactly("span", "log", "error")
      expect(backend_rows.find { |row| row[:type] == "span" }[:evidence]).to eq("parent_span")
      expect(backend_rows.map { |row| row[:trace_id] }.uniq).to eq([ fixture.dig("headers", "traceparent").split("-")[1] ])
      expect(backend_rows.map { |row| row[:release] }.uniq).to eq([ "test-release" ])

      sign_in users(:one)
      get correlations_project_event_path(mobile, anchor)
      expect(response.body).to include("Parent span", "Shared trace")
    end
  end
end
