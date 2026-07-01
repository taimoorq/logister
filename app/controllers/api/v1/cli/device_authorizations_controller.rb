# frozen_string_literal: true

class Api::V1::Cli::DeviceAuthorizationsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false

  def create
    authorization = CliDeviceAuthorization.issue!(
      client_name: client_name_param,
      requested_scopes: requested_scopes
    )

    render json: {
      device_code: authorization.plain_device_code,
      user_code: authorization.user_code_display,
      verification_uri: cli_device_authorization_url,
      verification_uri_complete: cli_device_authorization_url(user_code: authorization.user_code_display),
      expires_in: authorization.expires_at.to_i - Time.current.to_i,
      interval: CliDeviceAuthorization::DEFAULT_INTERVAL_SECONDS
    }, status: :created
  end

  def token
    authorization = CliDeviceAuthorization.find_by_device_code(params[:device_code])
    return render_device_error(:invalid_grant, "Device authorization was not found.") unless authorization

    result = authorization.exchange!
    if result.access_token?
      render json: {
        access_token: result.access_token.plain_token,
        token_type: "Bearer",
        expires_at: result.access_token.expires_at.utc.iso8601,
        scope: result.access_token.scopes.join(" ")
      }
    else
      render_device_error(result.status, device_error_description(result.status))
    end
  end

  private

  def requested_scopes
    requested = scope_param.to_s.split(/\s+/).reject(&:blank?)
    requested.presence || CliAccessToken::READ_SCOPES
  end

  def client_name_param
    params[:client_name].presence || params.dig(:device_authorization, :client_name).presence
  end

  def scope_param
    params[:scope].presence || params.dig(:device_authorization, :scope).presence
  end

  def render_device_error(error, description)
    render json: {
      error: error.to_s,
      error_description: description,
      interval: CliDeviceAuthorization::DEFAULT_INTERVAL_SECONDS
    }, status: :bad_request
  end

  def device_error_description(status)
    {
      authorization_pending: "Waiting for browser approval.",
      slow_down: "The CLI is polling too quickly. Wait before polling again.",
      access_denied: "The browser approval was denied.",
      expired_token: "The device authorization expired. Start login again.",
      invalid_grant: "The device authorization is no longer valid."
    }.fetch(status.to_sym, "The device authorization is no longer valid.")
  end
end
