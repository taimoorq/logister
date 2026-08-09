class HealthController < ApplicationController
  skip_before_action :require_modern_browser, raise: false

  def release
    payload = Logister::RuntimeReleaseIdentity.call
    expires_now
    render json: payload, status: payload.fetch(:status) == "ok" ? :ok : :service_unavailable
  end

  def clickhouse
    client = Logister::ClickhouseClient.new
    schema_status = client.schema_status

    if !schema_status.fetch(:enabled)
      render json: { status: "disabled", clickhouse_enabled: false, clickhouse_mode: "disabled" }, status: :ok
    elsif schema_status.fetch(:ready)
      render json: { status: "ok", clickhouse_enabled: true, clickhouse_mode: Rails.configuration.x.logister.clickhouse_mode, clickhouse_ready: true }, status: :ok
    else
      render json: {
        status: "degraded",
        clickhouse_enabled: true,
        clickhouse_mode: Rails.configuration.x.logister.clickhouse_mode,
        clickhouse_ready: false,
        schema: schema_status.slice(:healthy, :database, :missing_tables, :present_tables, :event_type_columns, :schema_issues)
      }, status: :service_unavailable
    end
  ensure
    client&.close
  end
end
