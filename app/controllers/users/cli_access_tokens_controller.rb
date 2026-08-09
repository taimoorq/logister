# frozen_string_literal: true

class Users::CliAccessTokensController < ApplicationController
  before_action :authenticate_user!

  def destroy
    cli_access_token = current_user.cli_access_tokens.find_by!(uuid: params[:uuid])

    notice = if cli_access_token.active?
      cli_access_token.revoke!
      "CLI session revoked. That terminal must sign in again to access Logister."
    else
      "That CLI session was already inactive."
    end

    redirect_to profile_path(anchor: "cli-sessions"), notice: notice, status: :see_other
  end

  def destroy_all
    now = Time.current
    revoked_count = current_user.cli_access_tokens.active.update_all(revoked_at: now, updated_at: now)

    notice = case revoked_count
    when 0
      "No active CLI sessions needed revoking."
    when 1
      "Revoked 1 active CLI session. That terminal must sign in again."
    else
      "Revoked #{revoked_count} active CLI sessions. Those terminals must sign in again."
    end

    redirect_to profile_path(anchor: "cli-sessions"), notice: notice, status: :see_other
  end
end
