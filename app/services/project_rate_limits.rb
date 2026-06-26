# frozen_string_literal: true

class ProjectRateLimits
  def self.default_public_api_rate_limit_requests
    positive_integer_logister_config(
      :public_api_rate_limit_requests,
      Project::DEFAULT_PUBLIC_API_RATE_LIMIT_REQUESTS
    )
  end

  def self.default_public_api_rate_limit_period_seconds
    positive_integer_logister_config(
      :public_api_rate_limit_period_seconds,
      Project::DEFAULT_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS
    )
  end

  def self.default_public_api_auth_failure_rate_limit_requests
    positive_integer_logister_config(
      :public_api_auth_failure_rate_limit_requests,
      Project::DEFAULT_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS
    )
  end

  def self.positive_integer_logister_config(name, default)
    value = Rails.application.config.x.logister.public_send(name)
    value.to_i.positive? ? value.to_i : default
  rescue NoMethodError
    default
  end
  private_class_method :positive_integer_logister_config

  def initialize(project)
    @project = project
  end

  def public_api_rate_limit_requests_effective(default)
    project.public_api_rate_limit_requests_override || default
  end

  def public_api_rate_limit_period_seconds_effective(default)
    project.public_api_rate_limit_period_seconds_override || default
  end

  def public_api_auth_failure_rate_limit_requests_effective(default)
    project.public_api_auth_failure_rate_limit_requests_override || default
  end

  private

  attr_reader :project
end
