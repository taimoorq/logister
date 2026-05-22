class HealthController < ApplicationController
  skip_before_action :require_modern_browser, raise: false

  def clickhouse
    client = Logister::ClickhouseClient.new
    schema_status = client.schema_status

    if !schema_status.fetch(:enabled)
      render json: { status: "disabled", clickhouse_enabled: false }, status: :ok
    elsif schema_status.fetch(:ready)
      render json: { status: "ok", clickhouse_enabled: true, clickhouse_ready: true }, status: :ok
    else
      render json: {
        status: "degraded",
        clickhouse_enabled: true,
        clickhouse_ready: false,
        schema: schema_status.slice(:healthy, :database, :missing_tables, :present_tables)
      }, status: :service_unavailable
    end
  end
end
