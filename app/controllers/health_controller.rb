class HealthController < ApplicationController
  skip_before_action :require_modern_browser, raise: false

  def clickhouse
    client = Logister::ClickhouseClient.new

    if !client.enabled?
      render json: { status: "disabled", clickhouse_enabled: false }, status: :ok
    elsif client.healthy?
      render json: { status: "ok", clickhouse_enabled: true }, status: :ok
    else
      render json: { status: "degraded", clickhouse_enabled: true }, status: :service_unavailable
    end
  end
end
