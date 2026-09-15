# frozen_string_literal: true

module Api::V1::Cli::Responses
  private

  def cli_list_payload(items:, next_cursor: nil, generated_at: Time.current, **metadata)
    {
      items:,
      next_cursor:,
      generated_at: Logister::CliSerializer.timestamp(generated_at)
    }.merge(metadata).compact
  end

  def render_not_found
    render json: {
      error: "Not found",
      code: "not_found",
      message: "The requested resource was not found."
    }, status: :not_found
  end

  def render_ambiguous_project(error)
    render json: {
      error: "Ambiguous project",
      code: "ambiguous_project",
      message: "More than one accessible project uses '#{error.identifier}'. Use the project UUID instead."
    }, status: :conflict
  end

  def render_invalid_cursor
    render json: {
      error: "Invalid cursor",
      code: "invalid_cursor",
      message: "The cursor is invalid or does not match this project and filter set."
    }, status: :unprocessable_content
  end

  def render_invalid_parameter(error)
    render json: {
      error: "Invalid parameter",
      code: "invalid_parameter",
      message: error.message,
      parameter: error.parameter
    }.compact, status: :unprocessable_content
  end

  def render_query_timeout
    render json: {
      error: "Query unavailable",
      code: "query_timeout",
      message: "The query exceeded the server time limit. Narrow the time range or filters and try again."
    }, status: :service_unavailable
  end
end
