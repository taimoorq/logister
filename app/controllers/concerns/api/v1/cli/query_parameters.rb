# frozen_string_literal: true

module Api::V1::Cli::QueryParameters
  private

  def cli_limit(default: 50, max: 100)
    Logister::CliQuery.integer(params[:limit], parameter: "limit", default:, min: 1, max:)
  end

  def parse_cli_time(value)
    Logister::CliQuery.time(value, parameter: "timestamp")
  end

  def cli_since(default: nil)
    raw = params[:since].to_s.strip
    return default if raw.blank?

    Logister::CliQuery.relative_or_time(raw, parameter: "since")
  end

  def cli_time_range(default_duration: 24.hours, max_duration: 90.days)
    Logister::CliQuery.range(
      since_value: params[:since],
      until_value: params[:until],
      default_duration:,
      max_duration:
    )
  end

  def decode_cli_cursor(value, resource:, project_uuid:, filters:)
    return if value.blank?

    Logister::CliCursor.decode(value, resource:, project_uuid:, filters:)
  end

  def encode_cli_cursor(resource:, project_uuid:, filters:, timestamp:, uuid:)
    Logister::CliCursor.encode(resource:, project_uuid:, filters:, timestamp:, uuid:)
  end
end
