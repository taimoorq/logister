class Users::ProfilesController < ApplicationController
  ACTIVE_CLI_ACCESS_TOKEN_LIMIT = 25
  RECENT_CLI_ACCESS_TOKEN_LIMIT = 10
  RECENT_CLI_ACCESS_TOKEN_WINDOW = 30.days
  SAFE_CLI_ACCESS_TOKEN_FIELDS = %i[
    uuid
    name
    scopes
    all_projects
    expires_at
    revoked_at
    last_used_at
    created_at
  ].freeze

  before_action :authenticate_user!

  def show
    @user = current_user
    load_cli_access_tokens
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update(profile_params)
      redirect_to profile_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def load_cli_access_tokens
    now = Time.current
    recent_cutoff = now - RECENT_CLI_ACCESS_TOKEN_WINDOW
    safe_tokens = current_user.cli_access_tokens.select(*SAFE_CLI_ACCESS_TOKEN_FIELDS).readonly

    @active_cli_access_tokens, @active_cli_access_tokens_truncated = bounded_records(
      safe_tokens
        .where(revoked_at: nil)
        .where("cli_access_tokens.expires_at > ?", now)
        .order(created_at: :desc, uuid: :desc),
      ACTIVE_CLI_ACCESS_TOKEN_LIMIT
    )

    @recent_cli_access_tokens, @recent_cli_access_tokens_truncated = bounded_records(
      safe_tokens
        .where(
          <<~SQL.squish,
            cli_access_tokens.revoked_at >= :cutoff OR
              (cli_access_tokens.revoked_at IS NULL AND cli_access_tokens.expires_at BETWEEN :cutoff AND :now)
          SQL
          cutoff: recent_cutoff,
          now: now
        )
        .order(Arel.sql("COALESCE(cli_access_tokens.revoked_at, cli_access_tokens.expires_at) DESC"), uuid: :desc),
      RECENT_CLI_ACCESS_TOKEN_LIMIT
    )
  end

  def bounded_records(relation, limit)
    records = relation.limit(limit + 1).to_a
    [ records.first(limit), records.length > limit ]
  end

  def profile_params
    params.require(:user).permit(:name)
  end
end
