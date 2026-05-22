class HealthController < ApplicationController
  skip_before_action :require_modern_browser, raise: false

  def clickhouse
    client = Logister::ClickhouseClient.new

    if !client.enabled?
      render json: { status: "disabled", clickhouse_enabled: false }, status: :ok
    elsif client.ready?
      render json: { status: "ok", clickhouse_enabled: true, clickhouse_ready: true }, status: :ok
    else
      render json: {
        status: "degraded",
        clickhouse_enabled: true,
        clickhouse_ready: false,
        schema: client.schema_status.slice(:healthy, :database, :missing_tables, :present_tables)
      }, status: :service_unavailable
    end
  end
end
