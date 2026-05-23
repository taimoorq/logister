class AddRateLimitOverridesToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :public_api_rate_limit_requests_override, :integer
    add_column :projects, :public_api_rate_limit_period_seconds_override, :integer
    add_column :projects, :public_api_auth_failure_rate_limit_requests_override, :integer
  end
end
