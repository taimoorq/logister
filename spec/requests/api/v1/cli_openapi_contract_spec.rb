# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "CLI OpenAPI route contract" do
  let(:contract) { YAML.safe_load_file(Rails.root.join("docs/openapi.yaml")) }

  def normalized_rails_path(route)
    route.path.spec.to_s
         .delete_suffix("(.:format)")
         .sub("/projects/:uuid", "/projects/:project_uuid")
         .gsub(/:([a-z_]+)/, '{\1}')
  end

  it "keeps every CLI route and documented operation in parity" do
    rails_operations = Rails.application.routes.routes.filter_map do |route|
      next unless route.defaults[:controller].to_s.start_with?("api/v1/cli")

      verb = route.verb.to_s.downcase
      next unless verb.in?(%w[get post put patch delete])

      [ verb, normalized_rails_path(route) ]
    end.to_set
    contract_operations = contract.fetch("paths").flat_map do |path, operations|
      next [] unless path.start_with?("/api/v1/cli/")

      operations.filter_map do |verb, operation|
        [ verb, path ] if operation.is_a?(Hash) && verb.in?(%w[get post put patch delete])
      end
    end.to_set

    expect(contract_operations).to eq(rails_operations)
  end

  it "pins the additive 3.5 operation identifiers used by the CLI contract gate" do
    expected = {
      "/api/v1/cli/session" => "getCliSession",
      "/api/v1/cli/projects/{project_uuid}/traces" => "listCliTraces",
      "/api/v1/cli/projects/{project_uuid}/traces/{trace_id}" => "getCliTrace",
      "/api/v1/cli/projects/{project_uuid}/monitors" => "listCliMonitors",
      "/api/v1/cli/projects/{project_uuid}/monitors/{uuid}" => "getCliMonitor",
      "/api/v1/cli/projects/{project_uuid}/deployments" => "listCliDeployments",
      "/api/v1/cli/projects/{project_uuid}/deployments/{uuid}" => "getCliDeployment",
      "/api/v1/cli/projects/{project_uuid}/insights" => "getCliInsights",
      "/api/v1/cli/projects/{project_uuid}/metrics/catalog" => "getCliMetricCatalog",
      "/api/v1/cli/projects/{project_uuid}/metrics/query" => "queryCliMetric"
    }

    expect(contract.dig("info", "version")).to eq("3.5")
    expected.each do |path, operation_id|
      expect(contract.dig("paths", path, "get", "operationId")).to eq(operation_id)
    end
  end

  it "documents authenticated CLI throttling, query timeouts, and bounded cursors on every GET read" do
    contract.fetch("paths").each do |path, operations|
      get = operations["get"]
      next unless path.start_with?("/api/v1/cli/") && get&.fetch("security", [])&.any? { |entry| entry.key?("cliBearerAuth") }

      expect(get.fetch("responses")).to include("429"), "expected #{path} to document 429"
      expect(get.fetch("responses")).to include("503"), "expected #{path} to document 503"
      expect(get.dig("responses", "503", "$ref")).to eq("#/components/responses/CliQueryUnavailable")
    end

    expect(contract.dig("components", "parameters", "Cursor", "schema", "maxLength")).to eq(8192)
    expect(contract.dig("components", "parameters", "AfterCursor", "schema", "maxLength")).to eq(8192)
  end

  it "contracts retention-aware analytics and bounded AI context metadata" do
    analytics = contract.dig("components", "schemas", "CliAnalytics")
    fallback = analytics.dig("properties", "fallback_coverage")
    ai_context = contract.dig("components", "schemas", "CliAiContext")
    token_budget = contract.dig(
      "paths",
      "/api/v1/cli/projects/{project_uuid}/error_groups/{uuid}/context",
      "get",
      "parameters"
    ).find { |parameter| parameter["name"] == "token_budget" }

    expect(analytics.fetch("required")).to include("source", "partial")
    expect(fallback.fetch("required")).to contain_exactly("complete", "reason", "requested_from", "requested_to")
    expect(fallback.dig("properties", "retained_from", "format")).to eq("date-time")
    expect(ai_context.fetch("required")).to include("token_budget", "response_byte_limit", "truncated")
    expect(ai_context.dig("properties", "response_byte_limit")).to include(
      "minimum" => 1024,
      "maximum" => 262_144
    )
    expect(token_budget.fetch("schema")).to include(
      "minimum" => 256,
      "maximum" => 32_000,
      "default" => 4_000
    )
  end

  it "documents repeatable Insights arrays without changing the scalar metric query" do
    expect(contract.dig("components", "parameters", "Metric", "name")).to eq("metric[]")
    expect(contract.dig("components", "parameters", "Attribute", "name")).to eq("attribute[]")

    insights_parameters = contract.dig("paths", "/api/v1/cli/projects/{project_uuid}/insights", "get", "parameters")
    expect(insights_parameters.pluck("$ref")).to include(
      "#/components/parameters/Metric",
      "#/components/parameters/Attribute"
    )

    query_parameters = contract.dig("paths", "/api/v1/cli/projects/{project_uuid}/metrics/query", "get", "parameters")
    scalar_metric = query_parameters.find { |parameter| parameter.is_a?(Hash) && parameter["name"] == "metric" }
    expect(scalar_metric).to include("in" => "query", "required" => true)
    expect(scalar_metric.dig("schema", "type")).to eq("string")
    expect(query_parameters.pluck("name").compact.grep(/\Ametric/)).to eq([ "metric" ])
  end
end
